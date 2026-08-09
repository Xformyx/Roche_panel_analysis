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
 * Always hard-link BAM+BAI into results/.../output/bam/ so IGV can access them
 * without manual copying and without extra disk usage (hard link = same inode).
 * When delete_intermediate is true, the work-dir copy is also removed by Nextflow,
 * but the hard-linked results copy survives because the inode refcount stays > 0.
 */
process SORT_SAM_COORDINATE_FINAL {
    tag "$sample_id"
    label 'process_medium'

    publishDir { "${params.outdir}/${sample_id}/output/bam" }, mode: 'link', pattern: "*.{bam,bai}", overwrite: true

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
