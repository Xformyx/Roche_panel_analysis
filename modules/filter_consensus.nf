process FILTER_CONSENSUS {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(consensus_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai

    output:
    tuple val(sample_id), path("${sample_id}_consensus_filtered.bam"), emit: filtered_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    java ${java_opts} -jar \${FGBIO_JAR} FilterConsensusReads \
        -i ${consensus_bam} \
        -o ${sample_id}_consensus_filtered.bam \
        --ref=${genome_fasta} \
        --max-read-error-rate=${params.max_read_error_rate} \
        --max-base-error-rate=${params.max_base_error_rate} \
        --max-no-call-fraction=${params.max_no_call_fraction} \
        --min-base-quality=${params.min_base_quality} \
        --min-reads=${params.min_reads} \
        --reverse-per-base-tags=true
    """
}
