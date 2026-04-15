process MERGE_BAM_ALIGNMENT {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(aligned_bam), path(unmapped_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai

    output:
    tuple val(sample_id), path("${sample_id}_merged.bam"), emit: merged_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" MergeBamAlignment \
        --ATTRIBUTES_TO_RETAIN XO \
        --ATTRIBUTES_TO_REMOVE NM \
        --ATTRIBUTES_TO_REMOVE MD \
        --ALIGNED_BAM ${aligned_bam} \
        --UNMAPPED_BAM ${unmapped_bam} \
        --OUTPUT ${sample_id}_merged.bam \
        --REFERENCE_SEQUENCE ${genome_fasta} \
        --SORT_ORDER queryname \
        --ALIGNED_READS_ONLY true \
        --MAX_INSERTIONS_OR_DELETIONS -1 \
        --PRIMARY_ALIGNMENT_STRATEGY MostDistant \
        --ALIGNER_PROPER_PAIR_FLAGS true \
        --CLIP_OVERLAPPING_READS false
    """
}

process MERGE_CONSENSUS_BAM {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(aligned_bam), path(unmapped_bam)
    path  genome_fasta
    path  genome_dict
    path  genome_fai

    output:
    tuple val(sample_id), path("${sample_id}_umi_deduped_sorted.bam"), emit: deduped_bam

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" MergeBamAlignment \
        --ATTRIBUTES_TO_RETAIN XO \
        --ATTRIBUTES_TO_RETAIN RX \
        --ALIGNED_BAM ${aligned_bam} \
        --UNMAPPED_BAM ${unmapped_bam} \
        --OUTPUT ${sample_id}_umi_deduped_sorted.bam \
        --REFERENCE_SEQUENCE ${genome_fasta} \
        --SORT_ORDER coordinate \
        --ADD_MATE_CIGAR true \
        --MAX_INSERTIONS_OR_DELETIONS -1 \
        --PRIMARY_ALIGNMENT_STRATEGY MostDistant \
        --ALIGNER_PROPER_PAIR_FLAGS true \
        --CLIP_OVERLAPPING_READS false \
        --ADD_PG_TAG_TO_READS false \
        --UNMAPPED_READ_STRATEGY COPY_TO_TAG \
        --ORIENTATIONS FR \
        --CREATE_INDEX true
    """
}
