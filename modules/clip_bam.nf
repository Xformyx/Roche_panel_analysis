process CLIP_BAM {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/QC_report" }, mode: params.publish_dir_mode,
        pattern: "*_clipov_metrics.txt"

    input:
    tuple val(sample_id), path(input_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai

    output:
    tuple val(sample_id), path("${sample_id}_clipped.bam"),         emit: clipped_bam
    tuple val(sample_id), path("${sample_id}_clipov_metrics.txt"),  emit: metrics

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    java ${java_opts} -jar \${FGBIO_JAR} ClipBam \
        --clip-overlapping-reads \
        -i ${input_bam} \
        -o ${sample_id}_clipped.bam \
        -m ${sample_id}_clipov_metrics.txt \
        -r ${genome_fasta}
    """
}
