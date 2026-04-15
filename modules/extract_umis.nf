process EXTRACT_UMIS {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(unmapped_bam)

    output:
    tuple val(sample_id), path("${sample_id}_umi_extracted.bam"), emit: umi_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    java ${java_opts} -jar \${FGBIO_JAR} ExtractUmisFromBam \
        -i ${unmapped_bam} \
        -o ${sample_id}_umi_extracted.bam \
        -r 3M3S+T 3M3S+T \
        -t RX \
        -a true
    """
}
