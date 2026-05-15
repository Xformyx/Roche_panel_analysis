/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RSeQC  —  RNA-seq specific QC metrics
 *
 *  RSEQC_INFER_EXPERIMENT  : Detect strandedness
 *  RSEQC_INNER_DISTANCE    : Inner distance between read pairs
 *  RSEQC_JUNCTION_SATURATION : Junction saturation (splice coverage)
 *  RSEQC_READ_DISTRIBUTION : Read distribution across genomic features
 *  RSEQC_TIN               : Transcript Integrity Number (RNA degradation)
 * ─────────────────────────────────────────────────────────────────────────────
 */

process RSEQC_INFER_EXPERIMENT {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report/rseqc" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    tuple val(sample_id2), path(bai)
    path bed12

    output:
    tuple val(sample_id), path("${sample_id}_infer_experiment.txt"), emit: txt

    script:
    """
    infer_experiment.py \\
        -i ${bam} \\
        -r ${bed12} \\
        > ${sample_id}_infer_experiment.txt
    """
}

process RSEQC_INNER_DISTANCE {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report/rseqc" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    tuple val(sample_id2), path(bai)
    path bed12

    output:
    tuple val(sample_id), path("${sample_id}_inner_distance*"), emit: results

    script:
    """
    inner_distance.py \\
        -i ${bam} \\
        -r ${bed12} \\
        -o ${sample_id}_inner_distance
    """
}

process RSEQC_JUNCTION_SATURATION {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report/rseqc" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    tuple val(sample_id2), path(bai)
    path bed12

    output:
    tuple val(sample_id), path("${sample_id}_junction_saturation*"), emit: results

    script:
    """
    junction_saturation.py \\
        -i ${bam} \\
        -r ${bed12} \\
        -o ${sample_id}_junction_saturation
    """
}

process RSEQC_READ_DISTRIBUTION {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report/rseqc" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    path bed12

    output:
    tuple val(sample_id), path("${sample_id}_read_distribution.txt"), emit: txt

    script:
    """
    read_distribution.py \\
        -i ${bam} \\
        -r ${bed12} \\
        > ${sample_id}_read_distribution.txt
    """
}

process RSEQC_TIN {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report/rseqc" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    tuple val(sample_id2), path(bai)
    path bed12

    output:
    tuple val(sample_id), path("${sample_id}*.tin.xls"), emit: xls
    tuple val(sample_id), path("${sample_id}*.summary.txt"), emit: summary

    script:
    // tin.py is single-threaded and processes every transcript — extremely slow on
    // full-genome BED12 (~62k entries in gencode v44, 2-4 h per sample).
    // Subsampling to 5000 representative transcripts reduces runtime to ~10-15 min
    // while preserving statistical accuracy of the RNA-integrity estimate.
    def tin_sample = params.tin_sample_size ?: 5000
    """
    # Subsample BED12 to ${tin_sample} transcripts (skip header lines starting with #)
    grep -v '^#' ${bed12} | shuf -n ${tin_sample} --random-source=${bam} > tin_subset.bed

    tin.py \\
        -i ${bam} \\
        -r tin_subset.bed

    # Rename outputs to match expected pattern
    for f in *.tin.xls *.summary.txt; do
        [ -f "\$f" ] || continue
        base=\$(basename "\$f")
        [[ "\$base" == ${sample_id}* ]] || mv "\$f" "${sample_id}_\$base"
    done
    """
}
