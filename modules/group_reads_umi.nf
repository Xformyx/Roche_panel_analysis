process GROUP_READS_BY_UMI {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode,
        pattern: "*_umi_group_data.tsv"

    input:
    tuple val(sample_id), path(merged_bam)

    output:
    tuple val(sample_id), path("${sample_id}_umi_grouped.bam"),      emit: grouped_bam
    tuple val(sample_id), path("${sample_id}_umi_group_data.tsv"),   emit: group_data

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    java ${java_opts} -jar \${FGBIO_JAR} GroupReadsByUmi \
        -i ${merged_bam} \
        -o ${sample_id}_umi_grouped.bam \
        --strategy=adjacency \
        --edits=1 \
        --min-map-q=20 \
        -t RX \
        -f ${sample_id}_umi_group_data.tsv
    """
}
