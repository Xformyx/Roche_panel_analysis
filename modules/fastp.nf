process FASTP {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/trimming" }, mode: params.publish_dir_mode,
        saveAs: { fn -> fn.endsWith(".fastq.gz") ? null : fn }

    input:
    tuple val(sample_id), path(fastq_r1), path(fastq_r2)

    output:
    // emit: reads  — used by RNAseq pipeline (STAR expects gzip FASTQ)
    // emit: trimmed — kept for ctDNA pipeline backward compatibility
    tuple val(sample_id), path("${sample_id}_trimmed_R1.fastq.gz"), path("${sample_id}_trimmed_R2.fastq.gz"), emit: reads
    tuple val(sample_id), path("${sample_id}_trimmed_R1.fastq.gz"), path("${sample_id}_trimmed_R2.fastq.gz"), emit: trimmed
    tuple val(sample_id), path("fastp.json"), path("fastp.html"), emit: report

    script:
    def extra = params.fastp_options ?: '-g -W 5 -q 20 -u 40 -x -3 -l 50 -c'
    """
    fastp \\
        -i ${fastq_r1} -o ${sample_id}_trimmed_R1.fastq.gz \\
        -I ${fastq_r2} -O ${sample_id}_trimmed_R2.fastq.gz \\
        --json fastp.json --html fastp.html \\
        ${extra} \\
        -w ${task.cpus}
    """
}
