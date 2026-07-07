process BED_TO_INTERVAL_LIST {
    tag "$sample_id"
    label 'process_low'

    input:
    val   sample_id
    path  bed_file
    path  genome_dict
    val   out_name      // e.g. "capture" or "primary"

    output:
    tuple val(sample_id), val(out_name), path("${out_name}.interval_list"), emit: interval_list

    script:
    """
    gatk BedToIntervalList \
        --INPUT ${bed_file} \
        --SEQUENCE_DICTIONARY ${genome_dict} \
        --OUTPUT ${out_name}.interval_list
    """
}

process COLLECT_HS_METRICS {
    tag "${sample_id} - ${bam_label}"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), val(bam_label), path(input_bam), path(bait_interval_list), path(target_interval_list)
    path  genome_fasta
    path  genome_dict
    path  genome_fai

    output:
    tuple val(sample_id), path("${sample_id}_hs_metrics_${bam_label}.txt"),            emit: hs_metrics
    tuple val(sample_id), path("${sample_id}_per_base_coverage_${bam_label}.txt"),     emit: per_base
    tuple val(sample_id), path("${sample_id}_per_target_coverage_${bam_label}.txt"),   emit: per_target

    script:
    """
    gatk CollectHsMetrics \
        --BAIT_INTERVALS ${bait_interval_list} \
        --BAIT_SET_NAME KAPA_HyperCap_DS_NHL_Panel \
        --TARGET_INTERVALS ${target_interval_list} \
        --INPUT ${input_bam} \
        --OUTPUT ${sample_id}_hs_metrics_${bam_label}.txt \
        --METRIC_ACCUMULATION_LEVEL ALL_READS \
        --REFERENCE_SEQUENCE ${genome_fasta} \
        --VALIDATION_STRINGENCY LENIENT \
        --COVERAGE_CAP 100000 \
        --PER_BASE_COVERAGE ${sample_id}_per_base_coverage_${bam_label}.txt \
        --PER_TARGET_COVERAGE ${sample_id}_per_target_coverage_${bam_label}.txt
    """
}
