process SNPSIFT_ANNOTATE {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/output${output_subdir ? '/' + output_subdir : ''}" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(input_vcf)
    path  dbsnp_vcf
    val   output_subdir

    output:
    tuple val(sample_id), path("${sample_id}_vardict_annotated.vcf"), emit: annotated_vcf

    script:
    def subdir_path = output_subdir ? "/${output_subdir}" : ""
    """
    java -jar \${SNPSIFT_JAR} annotate \
        -name DBSNP_ \
        -info "CAF, COMMON" \
        ${dbsnp_vcf} \
        ${input_vcf} \
    > ${sample_id}_vardict_annotated.vcf
    """
}
