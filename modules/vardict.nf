process VARDICT {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/output${output_subdir ? '/' + output_subdir : ''}" }, mode: params.publish_dir_mode, pattern: "*_vardict.vcf"

    input:
    tuple val(sample_id), path(input_bam), path(input_bai)
    path  genome_fasta
    path  genome_fai
    path  target_bed
    val   af_threshold
    val   output_subdir

    output:
    tuple val(sample_id), path("${sample_id}_vardict.vcf"), emit: vcf

    script:
    def subdir_path = output_subdir ? "/${output_subdir}" : ""
    def af_fmt = String.format("%.10f", af_threshold as double).replaceAll('0+$', '').replaceAll('\\.$', '')
    if (af_fmt.startsWith('.')) af_fmt = '0' + af_fmt
    """
    \${VARDICT_HOME}/bin/VarDict \
        -G ${genome_fasta} \
        -f ${af_fmt} \
        -N ${sample_id} \
        -b ${input_bam} \
        -c 1 -S 2 -E 3 -g 4 \
        ${target_bed} \
    | Rscript \${VARDICT_HOME}/bin/teststrandbias.R \
    | perl \${VARDICT_HOME}/bin/var2vcf_valid.pl \
        -N ${sample_id} -E -f ${af_fmt} \
    > ${sample_id}_vardict.vcf
    """
}
