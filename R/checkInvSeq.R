##' Checks if the two sequences are more or less reverse complement.
##' The reverse complement of the ALT is aligned to the REF and return TRUE if it aligns >80%.
##' @title Check if variants could be inversions
##' @param refseq the sequence of the reference allele
##' @param altseq the sequence of the alternate allele
##' @return a boolean vector representing if the variants are inversions
##' @author Jean Monlong
##' @keywords internal
checkInvSeq <- function(refseq, altseq){
    nottoolarge = which(Biostrings::nchar(refseq) * Biostrings::nchar(altseq) < 2e9)
    res = rep(FALSE, length(refseq))
    refseq = refseq[nottoolarge]
    altseq = altseq[nottoolarge]
    altseq = Biostrings::reverseComplement(altseq)
    pas = Biostrings::pairwiseAlignment(refseq, altseq)
    size = (Biostrings::nchar(refseq) + Biostrings::nchar(altseq)) / 2
    propinv = Biostrings::nmatch(pas) / size
    res[nottoolarge] = propinv>.8
    return(res)
}
