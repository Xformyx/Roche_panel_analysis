process SNPEFF {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(input_vcf)
    val   snpeff_db
    val   snpeff_data_dir

    output:
    tuple val(sample_id), path("${sample_id}_snpeff.vcf"), emit: annotated_vcf

    script:
    def datadir_opt = snpeff_data_dir ? "-dataDir ${snpeff_data_dir}" : ""
    """
    java -jar \${SNPEFF_JAR} \
        -v -noStats -noLog -canon \
        ${datadir_opt} \
        ${snpeff_db} \
        ${input_vcf} \
    > ${sample_id}_snpeff.vcf
    """
}
