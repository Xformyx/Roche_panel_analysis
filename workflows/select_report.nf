/*
 * Select Reporter Sub-workflow
 */

include { SELECT_REPORTERS } from '../modules/select_reporters'

workflow SELECT_REPORT {

    take:
    annotated_txt_ch   // tuple(sample_id, annotated_txt)
    germline_bam_ch    // tuple(sample_id, bam, bai)
    target_bed         // path

    main:

    // Join annotated variants with germline BAM
    input_ch = annotated_txt_ch
        .join(germline_bam_ch)
        .map { sid, txt, bam, bai -> tuple(sid, txt, bam, bai) }

    SELECT_REPORTERS(input_ch, target_bed)

    emit:
    reporters     = SELECT_REPORTERS.out.reporters
    all_reporters = SELECT_REPORTERS.out.all_reporters
}
