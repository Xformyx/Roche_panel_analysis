process LONGITUDINAL_ANALYSIS {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/output/longitudinal" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(followup_bam), path(followup_bai), path(reporters_txt)
    path  target_bed
    path  blocklist

    output:
    tuple val(sample_id), path("${sample_id}_longitudinal_analysis.csv"), emit: results

    script:
    """
    Rscript \${KAPA_NHL_R}/longitudinal_analysis.R \
        --reporters        ${reporters_txt} \
        --sample_bam       ${followup_bam} \
        --target_bed       ${target_bed} \
        --blocklist        ${blocklist} \
        --blist_type       variant \
        --output           ${sample_id}_longitudinal_analysis.csv \
        --reference        BSgenome.Hsapiens.UCSC.hg38 \
        --reads_threshold  ${params.la_reads_threshold} \
        --pvalue_threshold ${params.la_pvalue_threshold} \
        --vaf_threshold    ${params.la_vaf_threshold} \
        --n_sim            ${params.la_n_sim} \
        --read_min_bq      30 \
        --read_min_mq      30 \
        --read_max_dp      20000
    """
}
