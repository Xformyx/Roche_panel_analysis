/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  FEATURECOUNTS  —  Subread featureCounts gene-level quantification
 *
 *  Outputs:
 *    counts   : raw count matrix (sample_id_counts.txt)
 *    summary  : assignment summary (for MultiQC)
 * ─────────────────────────────────────────────────────────────────────────────
 */
process FEATURECOUNTS {
    tag "$sample_id"
    label 'process_medium'
    publishDir "${params.outdir}/${sample_id}/featureCounts", mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    path gtf

    output:
    tuple val(sample_id), path("${sample_id}_counts.txt"),         emit: counts
    tuple val(sample_id), path("${sample_id}_counts.txt.summary"), emit: summary

    script:
    """
    featureCounts \\
        -T ${task.cpus} \\
        -p -B -C \\
        --byReadGroup \\
        -a ${gtf} \\
        -o ${sample_id}_counts.txt \\
        ${bam}
    """
}
