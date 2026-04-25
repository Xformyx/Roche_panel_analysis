/*
 * Standard (non-UMI) Preprocessing Sub-workflow
 *
 * FASTQ -> [optional subsample] -> fastp -> BWA align -> coord sort ->
 * MarkDuplicates (REMOVE_DUPLICATES=true) -> clip overlapping reads ->
 * final sorted BAM
 *
 * Emits the same channel shapes as UMI_PREPROCESSING so downstream
 * VARIANT_CALLING / QC_REPORT / SELECT_REPORT / LONGITUDINAL workflows
 * are unchanged.
 */

include { FASTP                                       } from '../modules/fastp'
include { SEQTK_SUBSAMPLE                              } from '../modules/seqtk_subsample'
include { BWA_ALIGN                                    } from '../modules/bwa_align'
include { SORT_SAM_COORDINATE as SORT_ALIGNED_COORD    } from '../modules/sort_sam'
include { SORT_SAM_COORDINATE_FINAL as SORT_FINAL_COORD } from '../modules/sort_sam'
include { CLIP_BAM                                     } from '../modules/clip_bam'

/*
 * MarkDuplicates with REMOVE_DUPLICATES=true.
 * Distinct from QC_REPORT's MARK_DUPLICATES (which emits metrics only)
 * because both can run in the same pipeline (this one produces the
 * working dedup BAM; QC's runs again on the aligned BAM for metrics).
 */
process MARK_DUPLICATES_PRIMARY {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(input_bam), path(input_bai)

    output:
    tuple val(sample_id), path("${sample_id}_dedup.bam"), path("${sample_id}_dedup.bai"), emit: dedup_bam
    tuple val(sample_id), path("${sample_id}_markduplicates_primary_metrics.txt"),       emit: metrics

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" MarkDuplicates \\
        --VALIDATION_STRINGENCY LENIENT \\
        -I ${input_bam} \\
        -O ${sample_id}_dedup.bam \\
        --METRICS_FILE ${sample_id}_markduplicates_primary_metrics.txt \\
        --REMOVE_DUPLICATES true \\
        --ASSUME_SORTED true \\
        --CREATE_INDEX true
    """
}

workflow STANDARD_PREPROCESSING {

    take:
    samples_ch    // tuple(sample_id, fastq_1, fastq_2)
    genome_fasta  // path
    genome_dict   // path
    genome_fai    // path
    genome_idx    // path (BWA index files)

    main:

    // 1. [Optional] Subsample raw FASTQ R1+R2 before any processing
    def fastp_input_ch
    if (params.subsample.toString() == 'true') {
        SEQTK_SUBSAMPLE(samples_ch)
        fastp_input_ch = SEQTK_SUBSAMPLE.out.subsampled
    } else {
        fastp_input_ch = samples_ch
    }

    // 2. Adapter + quality trimming
    FASTP(fastp_input_ch)

    // 3. BWA-MEM alignment
    BWA_ALIGN(FASTP.out.trimmed, genome_fasta, genome_idx)

    // 4. Coordinate-sort + index aligned BAM (also serves as QC "aligned" channel)
    SORT_ALIGNED_COORD(BWA_ALIGN.out.aligned_bam)

    // 5. MarkDuplicates (REMOVE_DUPLICATES=true)
    MARK_DUPLICATES_PRIMARY(SORT_ALIGNED_COORD.out.sorted_bam)

    // 6. Clip overlapping read pairs (helpful for variant calling)
    dedup_for_clip = MARK_DUPLICATES_PRIMARY.out.dedup_bam
        .map { sid, bam, bai -> tuple(sid, bam) }
    CLIP_BAM(dedup_for_clip, genome_fasta, genome_dict, genome_fai)

    // 7. Final coordinate sort + index → publishes to results/{sample}/output/bam/
    //    SORT_SAM_COORDINATE_FINAL emits "${baseName}_sorted.bam" so input
    //    "${sample}_clipped.bam" yields "${sample}_clipped_sorted.bam"
    //    matching the bypass-mode detection path in web_ui/app.py.
    SORT_FINAL_COORD(CLIP_BAM.out.clipped_bam)

    // QC channels — match UMI_PREPROCESSING emit shapes
    deduped_for_qc = MARK_DUPLICATES_PRIMARY.out.dedup_bam
        .map { sid, bam, bai -> tuple(sid, bam) }

    emit:
    final_bam    = SORT_FINAL_COORD.out.sorted_bam     // tuple(sid, bam, bai) — clipped sorted
    aligned_bam  = SORT_ALIGNED_COORD.out.sorted_bam   // tuple(sid, bam, bai) — first-pass for QC
    deduped_bam  = deduped_for_qc                      // tuple(sid, bam) — dedup-only, for QC "umi_deduped" label
    fastp_report = FASTP.out.report
}
