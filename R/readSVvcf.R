##' Read a VCF file that contains SVs and create a GRanges with relevant information, e.g. SV size or genotype quality.
##'
##' By default, the quality information is taken from the QUAL field. If all
##' values are NA or 0, the function will try other fields as speficied in
##' the "qual.field" vector. Fields can be from the INFO or FORMAT fields.
##' @title Read SVs from a VCF file
##' @param vcf.file the path to the VCF file
##' @param keep.ins.seq should it keep the inserted sequence? Default is FALSE.
##' @param sample.name the name of the sample to use. If NULL (default), use
##' first sample.
##' @param qual.field fields to use as quality. Will be tried in order.
##' @param check.inv should the sequence of MNV be compared to identify inversions. 
##' @return a GRanges object with relevant information.
##' @author Jean Monlong
##' @export
##' @examples
##' \dontrun{
##' calls.gr = readSVvcf('calls.vcf')
##' }
readSVvcf <- function(vcf.file, keep.ins.seq=FALSE, sample.name=NULL, qual.field=c('GQ', 'QUAL'), check.inv=FALSE){
  vcf = VariantAnnotation::readVcf(vcf.file, row.names=FALSE)
  gr = DelayedArray::rowRanges(vcf)
  ## If sample specified, retrieve appropriate GT
  GT.idx = 1
  if(!is.null(sample.name)){
    GT.idx = which(sample.name == colnames(VariantAnnotation::geno(vcf)$GT))
  } 
  gr$GT = unlist(VariantAnnotation::geno(vcf)$GT[, GT.idx])
  
  ## Remove obvious SNVs
  singlealt = which(unlist(lapply(Biostrings::nchar(gr$ALT), length))==1)
  alt.sa = unlist(Biostrings::nchar(gr$ALT[singlealt]))
  ref.sa = Biostrings::nchar(gr$REF[singlealt])
  snv.idx = singlealt[which(ref.sa==1 & alt.sa==1)]
  snv.idx = snv.idx[which(as.character(unlist(gr$ALT[snv.idx])) != as.character(gr$REF[snv.idx]))]
  if(length(snv.idx)>0){
    nonsnv.idx = setdiff(1:length(gr), snv.idx)
    gr = gr[nonsnv.idx]
    vcf = vcf[nonsnv.idx]
  }

  ## Remove "ref" variants
  nonrefs = which(gr$GT!='0' & gr$GT!='0/0'  & gr$GT!='0|0' & gr$GT!='./.' & gr$GT!='.')
  gr = gr[nonrefs]
  vcf = vcf[nonrefs]
  
  ## If no SVs
  if(length(vcf) == 0){
    gr$REF = gr$paramRangeID = gr$FILTER = NULL
    if(!keep.ins.seq){
      gr$ALT = NULL
    }
    return(gr)
  }

  ## Symbolic alleles or ALT/REF ?
  if('SVTYPE' %in% colnames(VariantAnnotation::info(vcf)) &
     any(c('END', 'SVLEN') %in% colnames(VariantAnnotation::info(vcf)))){
    ## Symbolic alleles
    gr$type = unlist(VariantAnnotation::info(vcf)$SVTYPE)
    if('SVLEN' %in% colnames(VariantAnnotation::info(vcf))){
      gr$size = abs(unlist(VariantAnnotation::info(vcf)$SVLEN))
      ## In case there is no END info later, init with SVLEN
      GenomicRanges::end(gr) = ifelse(gr$type=='INS',
                                      GenomicRanges::end(gr),
                                      GenomicRanges::start(gr) + gr$size)
    }
    if('END' %in% colnames(VariantAnnotation::info(vcf))){
      ## Set size if not already present
      if(all('size' != colnames(GenomicRanges::mcols(gr)))){
        gr$size = unlist(VariantAnnotation::info(vcf)$END)-GenomicRanges::start(gr)
        if('INSLEN' %in% colnames(VariantAnnotation::info(vcf))){
          gr$size = ifelse(gr$type=='INS',
                           abs(unlist(VariantAnnotation::info(vcf)$INSLEN)),
                           gr$size)
        } else {
          if(any('INS'==gr$type)){
            warning('Insertions in the VCF but no information about insertion size.')
          }
        }
      }
      GenomicRanges::end(gr) = ifelse(gr$type=='INS',
                                      GenomicRanges::end(gr),
                                      unlist(VariantAnnotation::info(vcf)$END))
    }
    gr$size = ifelse(gr$type=='INS',
                     gr$size,
                     GenomicRanges::width(gr))
  } else {
    ## ALT/REF
    ## Split non-ref alleles
    gt.s = strsplit(gr$GT, '[/\\|]')
    gt.s = lapply(gt.s, unique)
    idx = rep(1:length(gt.s), unlist(lapply(gt.s, length)))
    als = unlist(gt.s)
    nonref = which(als!='0' & als!='.')
    idx = idx[nonref]
    als = as.numeric(als[nonref])
    gr = gr[idx]
    gr$al = als
    vcf = vcf[idx]
    ## Get allele sequence
    gr$ALT = Biostrings::DNAStringSet(lapply(1:length(gr), function(ii) unlist(gr$ALT[[ii]][als[ii]])))
    ## Right-trim REF/ALT
    trim.size = estTrimSize(gr$REF, gr$ALT)
    idx.trim = which(trim.size>0)
    if(length(idx.trim)>0){
      gr$REF[idx.trim] = Biostrings::DNAStringSet(lapply(idx.trim, function(ii) {
        trim.end = Biostrings::nchar(gr$REF[[ii]]) - trim.size[ii]
        gr$REF[[ii]][1:trim.end]
      }))
      gr$ALT[idx.trim] = Biostrings::DNAStringSet(lapply(idx.trim, function(ii) {
        trim.end = Biostrings::nchar(gr$ALT[[ii]]) - trim.size[ii]
        gr$ALT[[ii]][1:trim.end]
      }))
    }
    ## Compare ALT/REF size to define SV type
    alt.s = Biostrings::nchar(gr$ALT)
    ref.s = Biostrings::nchar(gr$REF)
    gr$type = ifelse(alt.s>ref.s, 'INS', 'DEL')
    gr$type = ifelse(alt.s==ref.s, 'MNV', gr$type)
    gr$type = ifelse(alt.s==1 & ref.s==1, 'SNV', gr$type)
    ## Variants other than clear DEL, INS or SNV. 
    others = which(alt.s>10 & ref.s>10)
    if(length(others)>0 & check.inv){
      gr.inv = gr[others]
      ref.seq = gr.inv$REF
      isinv = checkInvSeq(gr.inv$REF, gr.inv$ALT)
      gr$type[others] = ifelse(isinv, 'INV', gr$type[others])      
    }    
    gr$size = ifelse(gr$type=='INS', alt.s, GenomicRanges::width(gr))
  }

  ## read support if available
  if('AD' %in% rownames(VariantAnnotation::geno(VariantAnnotation::header(vcf)))){
    ad.l = VariantAnnotation::geno(vcf)$AD[, GT.idx]
    gr$ref.cov = unlist(lapply(ad.l, '[', 1))
    gr$alt.cov = unlist(lapply(ad.l, '[', 2))
  } else if(all(c('RO', 'AO') %in% rownames(VariantAnnotation::geno(VariantAnnotation::header(vcf))))){
    gr$ref.cov = as.numeric(VariantAnnotation::geno(vcf)$RO)
    gr$alt.cov = unlist(lapply(VariantAnnotation::geno(vcf)$AO, '[', 1))
  } else {
    gr$alt.cov = gr$ref.cov = NA
  }

  ## Convert missing qualities to 0
  if(any(is.na(gr$QUAL))){
    gr$QUAL[which(is.na(gr$QUAL))] = 0
  }
  ## Extract quality information
  qual.found = FALSE
  qfield.ii = 1
  while(!qual.found & qfield.ii <= length(qual.field)){
    if(qual.field[qfield.ii] == 'QUAL' & any(gr$QUAL>0)){
      qual.found = TRUE
    } else if(qual.field[qfield.ii] %in% names(VariantAnnotation::geno(vcf))){
      qual.geno = VariantAnnotation::geno(vcf)[[qual.field[qfield.ii]]]
      if(length(dim(qual.geno)) == 3){
        ## Assuming that info for each allele starting with ref
        if('al' %in% colnames(gr)){
          ## If we know which allele to use
          gr$QUAL = unlist(qual.geno[, GT.idx, gr$al + 1])
        } else {
          ## Otherwise assume only one alt
          gr$QUAL = unlist(qual.geno[, GT.idx, 2])
        }
        qual.found = TRUE
      } else if(length(dim(qual.geno)) == 2){
        gr$QUAL = unlist(qual.geno[, GT.idx])
        qual.found = TRUE
      }
    } else if(qual.field[qfield.ii] %in% colnames(VariantAnnotation::info(vcf))){
      gr$QUAL = unlist(VariantAnnotation::info(vcf)[[qual.field[qfield.ii]]])
      qual.found = TRUE
    }
    qfield.ii = qfield.ii + 1
  }

  ## Group into het/hom
  homs = sapply(1:10, function(ii) paste0(ii, '/', ii))
  homs = c(homs, sapply(1:10, function(ii) paste0(ii, '|', ii)))
  gr$GT = ifelse(gr$GT %in% homs, 'hom', 'het')

  ## Remove unused columns
  gr$REF = gr$paramRangeID = gr$FILTER = gr$al = NULL
  if(!keep.ins.seq){
    gr$ALT = NULL
  }

  ## Remove SNVs and MNVs
  gr = gr[which(gr$type!='SNV' & gr$type!='MNV')]
  return(gr)
}
