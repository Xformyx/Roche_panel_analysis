process CALL_CONSENSUS {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(grouped_bam)

    output:
    tuple val(sample_id), path("${sample_id}_consensus_unmapped.bam"), emit: consensus_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    java ${java_opts} -jar \${FGBIO_JAR} CallMolecularConsensusReads \
        -i ${grouped_bam} \
        -o ${sample_id}_consensus_unmapped.bam \
        --error-rate-post-umi 40 \
        --error-rate-pre-umi 45 \
        --output-per-base-tags false \
        --min-reads ${params.min_reads} \
        --max-reads 100 \
        --min-input-base-quality ${params.min_base_quality} \
        --read-name-prefix='consensus'
    """
}
