process SEQTK_SUBSAMPLE {
    tag "$sample_id"
    label 'process_low'

    input:
    tuple val(sample_id), path(fastq_r1), path(fastq_r2)

    output:
    tuple val(sample_id), path("${sample_id}_subset_R1.fastq"), path("${sample_id}_subset_R2.fastq"), emit: subsampled

    script:
    """
    seqtk sample -s ${params.seqtk_seed} ${fastq_r1} ${params.seqtk_sample_size} > ${sample_id}_subset_R1.fastq
    seqtk sample -s ${params.seqtk_seed} ${fastq_r2} ${params.seqtk_sample_size} > ${sample_id}_subset_R2.fastq
    """
}
