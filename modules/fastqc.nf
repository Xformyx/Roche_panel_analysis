process FASTQC {
    tag "$sample_id"
    label 'process_low'
    publishDir "${params.outdir}/${sample_id}/fastqc", mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(fastq_1), path(fastq_2)

    output:
    tuple val(sample_id), path("*.html"), emit: html
    tuple val(sample_id), path("*.zip"),  emit: zip

    script:
    """
    fastqc -t ${task.cpus} -f fastq ${fastq_1} ${fastq_2} -o .
    """
}
