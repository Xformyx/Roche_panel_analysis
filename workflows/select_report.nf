/*
 * Select Reporter Sub-workflow
 */

include { SELECT_REPORTERS } from '../modules/select_reporters'

workflow SELECT_REPORT {

    take:
    annotated_txt_ch   // tuple(sample_id, annotated_txt)       — Baseline VCF txt
    germline_bam_ch    // tuple(sample_id, bam, bai)            — Germline BAM (S2)
    followup_bam_ch    // tuple(sample_id, bam, bai)            — Followup BAM (S5)
    blocklist          // path                                   — blocklist file

    main:

    // Join: (sid, baseline_txt) + (sid, germ_bam, germ_bai) + (sid, fol_bam, fol_bai)
    input_ch = annotated_txt_ch
        .join(germline_bam_ch)
        .join(followup_bam_ch)
        .map { sid, txt, germ_bam, germ_bai, fol_bam, fol_bai ->
               tuple(sid, txt, germ_bam, germ_bai, fol_bam, fol_bai) }

    SELECT_REPORTERS(input_ch, blocklist)

    emit:
    reporters     = SELECT_REPORTERS.out.reporters
    all_reporters = SELECT_REPORTERS.out.all_reporters
}
