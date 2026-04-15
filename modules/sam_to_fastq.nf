process SAM_TO_FASTQ {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(input_bam)

    output:
    tuple val(sample_id), path("${sample_id}_R1.fastq"), path("${sample_id}_R2.fastq"), emit: fastq

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" SamToFastq \
        -I ${input_bam} \
        -F ${sample_id}_R1.fastq \
        -F2 ${sample_id}_R2.fastq \
        --CLIPPING_ATTRIBUTE XT \
        --CLIPPING_ACTION 2
    """
}
