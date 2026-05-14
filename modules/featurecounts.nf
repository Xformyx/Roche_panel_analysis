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
    publishDir { "${params.outdir}/${sample_id}/featureCounts" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(bam)
    path gtf

    output:
    tuple val(sample_id), path("${sample_id}_counts.txt"),         emit: counts
    tuple val(sample_id), path("${sample_id}_counts.txt.summary"), emit: summary

    script:
    """
    # Auto-detect paired-end by checking BAM flags (0x1 = read paired)
    PE_COUNT=\$(samtools view -f 0x1 -c ${bam} 2>/dev/null || echo 0)
    if [ "\$PE_COUNT" -gt 0 ]; then
        PE_FLAGS="-p -B -C"
    else
        PE_FLAGS=""
    fi

    featureCounts \\
        -T ${task.cpus} \\
        \$PE_FLAGS \\
        -a ${gtf} \\
        -o ${sample_id}_counts.txt \\
        ${bam}
    
    """
}
