process BWA_ALIGN {
    tag "$sample_id"
    label 'process_high'

    input:
    tuple val(sample_id), path(fastq_r1), path(fastq_r2)
    path  genome_fasta
    path  genome_index_files

    output:
    tuple val(sample_id), path("${sample_id}_aligned.bam"), emit: aligned_bam

    script:
    def samtools_threads = Math.max(1, (task.cpus / 4) as int)
    """
    bwa mem \
        -R "@RG\\tID:A\\tDS:KAPA_TE\\tPL:ILLUMINA\\tLB:${sample_id}\\tSM:${sample_id}" \
        -t ${task.cpus} \
        -Y \
        ${genome_fasta} \
        ${fastq_r1} ${fastq_r2} \
    | samtools view -f2 -Sb -@ ${samtools_threads} - \
    > ${sample_id}_aligned.bam
    """
}

process BWA_CONSENSUS_ALIGN {
    tag "$sample_id"
    label 'process_high'

    input:
    tuple val(sample_id), path(fastq_r1), path(fastq_r2)
    path  genome_fasta
    path  genome_index_files

    output:
    tuple val(sample_id), path("${sample_id}_consensus_mapped.bam"), emit: consensus_bam

    script:
    def samtools_threads = Math.max(1, (task.cpus / 4) as int)
    """
    bwa mem \
        -R "@RG\\tID:A\\tDS:KAPA_TE\\tPL:ILLUMINA\\tLB:${sample_id}\\tSM:${sample_id}" \
        -t ${task.cpus} \
        -Y \
        ${genome_fasta} \
        ${fastq_r1} ${fastq_r2} \
    | samtools view -bh -@ ${samtools_threads} - \
    > ${sample_id}_consensus_mapped.bam
    """
}
