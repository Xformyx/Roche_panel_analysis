process UMI_QC {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(group_tsv), path(clipov_metrics), path(aln_metrics_aligned), path(aln_metrics_deduped)

    output:
    tuple val(sample_id), path("${sample_id}_umi_qc.json"), emit: json
    tuple val(sample_id), path("${sample_id}_umi_qc.txt"),  emit: txt
    tuple val(sample_id), path(group_tsv),                   emit: group_tsv

    script:
    def clip_arg = clipov_metrics.name != 'NO_FILE' ? "--clipov-metrics ${clipov_metrics}" : ''
    def aln_arg  = aln_metrics_aligned.name != 'NO_FILE' ? "--alignment-aligned ${aln_metrics_aligned}" : ''
    def ded_arg  = aln_metrics_deduped.name != 'NO_FILE' ? "--alignment-deduped ${aln_metrics_deduped}" : ''
    """
    umi_qc_summary.py \
        --sample-id ${sample_id} \
        --group-tsv ${group_tsv} \
        ${clip_arg} \
        ${aln_arg} \
        ${ded_arg} \
        --out-json ${sample_id}_umi_qc.json \
        --out-txt  ${sample_id}_umi_qc.txt
    """
}
