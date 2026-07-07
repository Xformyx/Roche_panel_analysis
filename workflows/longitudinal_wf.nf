/*
 * Longitudinal Analysis Sub-workflow
 */

include { LONGITUDINAL_ANALYSIS } from '../modules/longitudinal'

workflow LONGITUDINAL {

    take:
    followup_bam_ch   // tuple(sample_id, bam, bai)
    reporters_ch      // tuple(sample_id, reporters_txt)
    target_bed        // path
    blocklist         // path
    bsgenome          // val (e.g. BSgenome.Hsapiens.UCSC.hg38)

    main:

    // Join followup BAM with reporters
    input_ch = followup_bam_ch
        .join(reporters_ch)
        .map { sid, bam, bai, reporters -> tuple(sid, bam, bai, reporters) }

    LONGITUDINAL_ANALYSIS(input_ch, target_bed, blocklist, bsgenome)

    emit:
    results = LONGITUDINAL_ANALYSIS.out.results
}
