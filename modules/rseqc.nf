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
    """
    tin.py \\
        -i ${bam} \\
        -r ${bed12}
    """
}
