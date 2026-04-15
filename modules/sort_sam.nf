process SORT_SAM_QUERYNAME {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(input_bam)

    output:
    tuple val(sample_id), path("${input_bam.baseName}_qnsorted.bam"), emit: sorted_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" SortSam \
        -I ${input_bam} \
        -O ${input_bam.baseName}_qnsorted.bam \
        -SO queryname
    """
}

process SORT_SAM_COORDINATE {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(input_bam)

    output:
    tuple val(sample_id), path("${input_bam.baseName}_sorted.bam"), path("${input_bam.baseName}_sorted.bai"), emit: sorted_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" SortSam \
        I=${input_bam} \
        O=${input_bam.baseName}_sorted.bam \
        SORT_ORDER=coordinate \
        CREATE_INDEX=true
    """
}
