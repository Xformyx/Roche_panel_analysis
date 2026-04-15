process SELECT_REPORTERS {
    tag "$sample_id"
    label 'process_medium'
    publishDir "${params.outdir}/${sample_id}/output/select_report", mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(annotated_txt), path(germline_bam), path(germline_bai)
    path  target_bed

    output:
    tuple val(sample_id), path("${sample_id}_selected_baseline_reporters.txt"), emit: reporters
    tuple val(sample_id), path("${sample_id}_all_reporters.txt"),               emit: all_reporters, optional: true
    tuple val(sample_id), path("*.vcf"),                                        emit: vcf, optional: true

    script:
    """
    Rscript \${KAPA_NHL_R}/select_reporters.R \
        --baseline_variants ${annotated_txt} \
        --germline_bam ${germline_bam} \
        --followup_bam ${germline_bam} \
        --target_bed ${target_bed} \
        --output_dir . \
        --sample_name ${sample_id} \
        --germline_cutoff ${params.sr_germline_cutoff} \
        --min_af ${params.sr_min_af} \
        --max_af ${params.sr_max_af} \
        --min_dp ${params.sr_min_dp} \
        --min_vd ${params.sr_min_vd} \
        --min_mq ${params.sr_min_mq} \
        --min_qual ${params.sr_min_qual} \
        --min_sbf ${params.sr_min_sbf} \
        --max_nm ${params.sr_max_nm}
    """
}
