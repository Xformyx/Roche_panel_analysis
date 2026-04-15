process FASTQ_TO_SAM {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(fastq_1), path(fastq_2)

    output:
    tuple val(sample_id), path("${sample_id}_unmapped.bam"), emit: unmapped_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g -XX:ParallelGCThreads=${task.cpus}"
    """
    gatk --java-options "${java_opts}" FastqToSam \
        -F1 ${fastq_1} \
        -F2 ${fastq_2} \
        -O ${sample_id}_unmapped.bam \
        -SM ${sample_id} \
        --MAX_RECORDS_IN_RAM 2000000 \
        --COMPRESSION_LEVEL 5
    """
}
