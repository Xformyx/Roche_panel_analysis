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

process REFERENCE_BUILD_INFO {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    val   sample_id
    path  genome_fai
    val   reference_label
    val   fasta_name

    output:
    tuple val(sample_id), path("${sample_id}_reference_build.txt"), emit: info

    // The 'reference' label alone cannot identify the build: 'hg38' meant the
    // full 3,366-contig FASTA before 2026-08-26 and the 2,580-contig
    // primary-only FASTA after. Record the resolved identity so results stay
    // attributable and Longitudinal can refuse to mix builds.
    script:
    """
    contigs=\$(wc -l < ${genome_fai})
    alt=\$(cut -f1 ${genome_fai} | grep -cE '_alt\$|^HLA-' || true)
    {
        printf 'reference_label\\t%s\\n' '${reference_label}'
        printf 'fasta\\t%s\\n'           '${fasta_name}'
        printf 'contigs\\t%s\\n'         "\$contigs"
        printf 'alt_contigs\\t%s\\n'     "\$alt"
        printf 'build_tag\\t%s:%s\\n'    '${fasta_name}' "\$contigs"
    } > ${sample_id}_reference_build.txt
    """
}

process COUNT_READS {
    tag "${sample_id} - ${bam_label} [${bed_region}]"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), val(bam_label), path(input_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai
    path  target_bed
    val   bed_region   // 'capture' | 'primary' — used as suffix in output filename

    output:
    tuple val(sample_id), path("${sample_id}_ontarget_reads_${bam_label}_${bed_region}.txt"), emit: counts

    script:
    """
    gatk CountReads \
        -I ${input_bam} \
        -L ${target_bed} \
        --read-filter MappedReadFilter \
        --read-filter NotSecondaryAlignmentReadFilter \
        -R ${genome_fasta} \
    > ${sample_id}_ontarget_reads_${bam_label}_${bed_region}.txt
    """
}
