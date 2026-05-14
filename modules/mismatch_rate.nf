process MISMATCH_RATE {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode
    errorStrategy 'ignore'

    input:
    tuple val(sample_id), path(deduped_bam)
    path  target_bed
    path  blocklist
    val   bsgenome_ref

    output:
    tuple val(sample_id), path("${sample_id}_mismatch_rate.csv"), emit: mismatch, optional: true

    script:
    """
    samtools index ${deduped_bam}
    Rscript \${KAPA_NHL_R}/mismatch_rate.R \
        --sample_bam ${deduped_bam} \
        --target_bed ${target_bed} \
        --vaf_threshold 0.05 \
        --read_min_bq 30 \
        --read_min_mq 30 \
        --read_max_dp 20000 \
        --blocklist ${blocklist} \
        --blist_type variant \
        --output ${sample_id}_mismatch_rate.csv \
        --reference ${bsgenome_ref}
    """
}
