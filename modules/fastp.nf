process FASTP {
    tag "$sample_id"
    label 'process_low'
    publishDir "${params.outdir}/${sample_id}/trimming", mode: params.publish_dir_mode, pattern: "*.{json,html}"

    input:
    tuple val(sample_id), path(fastq_r1), path(fastq_r2)

    output:
    tuple val(sample_id), path("${sample_id}_trimmed_R1.fastq"), path("${sample_id}_trimmed_R2.fastq"), emit: trimmed
    tuple val(sample_id), path("fastp.json"), path("fastp.html"), emit: report

    script:
    """
    fastp \
        -i ${fastq_r1} -o ${sample_id}_trimmed_R1.fastq \
        -I ${fastq_r2} -O ${sample_id}_trimmed_R2.fastq \
        --json fastp.json --html fastp.html \
        ${params.fastp_options} \
        -w ${task.cpus}
    """
}
