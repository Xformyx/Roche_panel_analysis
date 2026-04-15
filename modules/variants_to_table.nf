process VARIANTS_TO_TABLE {
    tag "$sample_id"
    label 'process_low'
    publishDir { "${params.outdir}/${sample_id}/output${output_subdir ? '/' + output_subdir : ''}" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(annotated_vcf)
    val   output_subdir

    output:
    tuple val(sample_id), path("${sample_id}_vardict_annotated_vcf.txt"), emit: table

    script:
    def subdir_path = output_subdir ? "/${output_subdir}" : ""
    """
    gatk VariantsToTable \
        -V ${annotated_vcf} \
        --show-filtered \
        -O ${sample_id}_vardict_annotated_vcf.txt \
        -F CHROM -F POS -F REF -F ALT -F ID -F FILTER \
        -F ADJAF -F AF -F BIAS -F DP -F VD -F DUPRATE \
        -F END -F HIAF -F MQ -F HICNT -F HICOV -F LSEQ \
        -F RSEQ -F NM -F PSTD -F QSTD -F QUAL \
        -F REFBIAS -F VARBIAS -F SBF -F SN -F TYPE \
        -F DP4 -F HRUN -F SB -F DBSNP_CAF -F DBSNP_COMMON \
        -F ANN \
        -GF AD -GF ALD -GF GT -GF RD
    """
}
