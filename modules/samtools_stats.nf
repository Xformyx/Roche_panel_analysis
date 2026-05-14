/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  SAMTOOLS_FLAGSTAT  —  Alignment statistics from samtools flagstat
 *  SAMTOOLS_IDXSTATS  —  Per-chromosome read counts from samtools idxstats
 *  SAMTOOLS_STATS     —  Comprehensive BAM statistics from samtools stats
 * ─────────────────────────────────────────────────────────────────────────────
 */

process SAMTOOLS_FLAGSTAT {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)

    output:
    tuple val(sample_id), path("${sample_id}_flagstat.txt"), emit: flagstat

    script:
    """
    samtools flagstat -@ ${task.cpus} ${bam} > ${sample_id}_flagstat.txt
    """
}

process SAMTOOLS_IDXSTATS {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    tuple val(sample_id2), path(bai)

    output:
    tuple val(sample_id), path("${sample_id}_idxstats.txt"), emit: idxstats

    script:
    """
    samtools idxstats ${bam} > ${sample_id}_idxstats.txt
    """
}

process SAMTOOLS_STATS {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)

    output:
    tuple val(sample_id), path("${sample_id}_samtools_stats.txt"), emit: stats

    script:
    """
    samtools stats -@ ${task.cpus} ${bam} > ${sample_id}_samtools_stats.txt
    """
}
