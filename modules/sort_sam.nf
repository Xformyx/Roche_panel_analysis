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

/*
 * Coordinate-sort for VarDict input (clip-overlap final BAM).
 * When delete_intermediate is true, publish BAM+BAI under results/.../output/bam/ before work-dir cleanup
 * so VarDict input is retained after Nextflow removes task work directories.
 */
process SORT_SAM_COORDINATE_FINAL {
    tag "$sample_id"
    label 'process_medium'

    publishDir "${params.outdir}/${sample_id}/output/bam", mode: params.publish_dir_mode, pattern: "*.{bam,bai}", enabled: params.delete_intermediate

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
