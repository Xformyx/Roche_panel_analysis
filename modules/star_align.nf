/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  STAR_ALIGN  —  STAR 2-pass alignment for RNA-seq
 *
 *  Outputs:
 *    bam            : sorted BAM (coordinate)
 *    bai            : BAM index
 *    log_final      : STAR final alignment log (for MultiQC)
 *    log_progress   : STAR progress log
 *    reads_per_gene : per-gene read counts (GeneCounts mode)
 *    sj             : splice junction table
 * ─────────────────────────────────────────────────────────────────────────────
 */
process STAR_ALIGN {
    tag "$sample_id"
    label 'process_high'
    publishDir { "${params.outdir}/${sample_id}/star" }, mode: params.publish_dir_mode,
        saveAs: { fn ->
            if (fn.endsWith("_Log.final.out"))      return "log/${fn}"
            if (fn.endsWith("_Log.out"))             return "log/${fn}"
            if (fn.endsWith("_Log.progress.out"))    return "log/${fn}"
            if (fn.endsWith(".bam") || fn.endsWith(".bai")) return "bam/${fn}"
            if (fn.endsWith("ReadsPerGene.out.tab")) return "counts/${fn}"
            if (fn.endsWith("SJ.out.tab"))           return "junctions/${fn}"
            return fn
        }

    input:
    tuple val(sample_id), path(fastq_1), path(fastq_2)
    path star_index

    output:
    tuple val(sample_id), path("${sample_id}_Aligned.sortedByCoord.out.bam"),     emit: bam
    tuple val(sample_id), path("${sample_id}_Aligned.sortedByCoord.out.bam.bai"), emit: bai
    tuple val(sample_id), path("${sample_id}_Log.final.out"),                      emit: log_final
    tuple val(sample_id), path("${sample_id}_Log.out"),                            emit: log_out
    tuple val(sample_id), path("${sample_id}_Log.progress.out"),                   emit: log_progress
    tuple val(sample_id), path("${sample_id}_ReadsPerGene.out.tab"),               emit: reads_per_gene
    tuple val(sample_id), path("${sample_id}_SJ.out.tab"),                         emit: sj
    tuple val(sample_id), path("${sample_id}_Chimeric.out.junction"),              emit: chimeric_junction

    script:
    """
    STAR \\
        --runThreadN ${task.cpus} \\
        --genomeDir ${star_index} \\
        --readFilesIn ${fastq_1} ${fastq_2} \\
        --readFilesCommand zcat \\
        --outFileNamePrefix ${sample_id}_ \\
        --outSAMtype BAM SortedByCoordinate \\
        --outSAMunmapped Within \\
        --outSAMattributes NH HI AS NM MD \\
        --outFilterType BySJout \\
        --outFilterMultimapNmax 20 \\
        --alignSJoverhangMin 8 \\
        --alignSJDBoverhangMin 1 \\
        --outFilterMismatchNmax 999 \\
        --outFilterMismatchNoverReadLmax 0.04 \\
        --alignIntronMin 20 \\
        --alignIntronMax 1000000 \\
        --alignMatesGapMax 1000000 \\
        --quantMode GeneCounts \\
        --twopassMode Basic \\
        --outWigType bedGraph \\
        --outWigStrand Stranded \\
        --chimSegmentMin 12 \\
        --chimJunctionOverhangMin 8 \\
        --chimOutJunctionFormat 1 \\
        --chimMultimapScoreRange 3 \\
        --chimMultimapNmax 20 \\
        --chimNonchimScoreDropMin 10 \\
        --peOverlapNbasesMin 12 \\
        --peOverlapMMp 0.1 \\
        --alignSJstitchMismatchNmax 5 -1 5 5

    samtools index -@ ${task.cpus} ${sample_id}_Aligned.sortedByCoord.out.bam
    """
}
