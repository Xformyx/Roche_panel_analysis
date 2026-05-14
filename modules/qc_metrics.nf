process COLLECT_ALIGNMENT_METRICS {
    tag "${sample_id} - ${bam_label}"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), val(bam_label), path(input_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai

    output:
    tuple val(sample_id), path("${sample_id}_alignment_metrics_${bam_label}.txt"), emit: metrics

    script:
    """
    gatk CollectAlignmentSummaryMetrics \
        --METRIC_ACCUMULATION_LEVEL ALL_READS \
        --INPUT ${input_bam} \
        --OUTPUT ${sample_id}_alignment_metrics_${bam_label}.txt \
        --REFERENCE_SEQUENCE ${genome_fasta} \
        --VALIDATION_STRINGENCY LENIENT
    """
}

process MARK_DUPLICATES {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(input_bam)

    output:
    tuple val(sample_id), path("${sample_id}_sorted_rmdups.bam"),                emit: dedup_bam
    tuple val(sample_id), path("${sample_id}_sorted_rmdups.bai"),                emit: dedup_bai
    tuple val(sample_id), path("${sample_id}_markduplicates_metrics_gatk.txt"),  emit: metrics

    script:
    """
    gatk MarkDuplicates \
        --VALIDATION_STRINGENCY LENIENT \
        -I ${input_bam} \
        -O ${sample_id}_sorted_rmdups.bam \
        --METRICS_FILE ${sample_id}_markduplicates_metrics_gatk.txt \
        --REMOVE_DUPLICATES true \
        --ASSUME_SORTED true \
        --CREATE_INDEX true
    """
}

process COLLECT_INSERT_SIZE {
    tag "${sample_id} - ${bam_label}"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), val(bam_label), path(input_bam)

    output:
    tuple val(sample_id), path("${sample_id}_insert_size_metrics_${bam_label}.txt"),  emit: metrics
    tuple val(sample_id), path("${sample_id}_insert_size_plot_${bam_label}.pdf"),     emit: plot

    script:
    """
    gatk CollectInsertSizeMetrics \
        --VALIDATION_STRINGENCY LENIENT \
        -H ${sample_id}_insert_size_plot_${bam_label}.pdf \
        -I ${input_bam} \
        -O ${sample_id}_insert_size_metrics_${bam_label}.txt
    """
}

process COUNT_READS {
    tag "${sample_id} - ${bam_label}"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), val(bam_label), path(input_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai
    path  target_bed

    output:
    tuple val(sample_id), path("${sample_id}_ontarget_reads_${bam_label}.txt"), emit: counts

    script:
    """
    gatk CountReads \
        -I ${input_bam} \
        -L ${target_bed} \
        --read-filter MappedReadFilter \
        --read-filter NotSecondaryAlignmentReadFilter \
        -R ${genome_fasta} \
    > ${sample_id}_ontarget_reads_${bam_label}.txt
    """
}
