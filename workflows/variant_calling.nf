/*
 * Variant Calling Sub-workflow
 *
 * Final BAM -> VarDict -> SnpEff -> SnpSift -> VariantsToTable
 */

include { VARDICT            } from '../modules/vardict'
include { SNPEFF             } from '../modules/snpeff'
include { SNPSIFT_ANNOTATE   } from '../modules/snpsift'
include { VARIANTS_TO_TABLE  } from '../modules/variants_to_table'

workflow VARIANT_CALLING {

    take:
    final_bam_ch    // tuple(sample_id, bam, bai)
    genome_fasta    // path
    genome_fai      // path
    target_bed      // path
    dbsnp_vcf       // path
    af_threshold    // val
    snpeff_db       // val
    output_subdir   // val

    main:

    // 1. VarDict variant calling
    VARDICT(final_bam_ch, genome_fasta, genome_fai, target_bed, af_threshold, output_subdir)

    // 2. SnpEff gene annotation
    SNPEFF(VARDICT.out.vcf, snpeff_db, params.snpeff_data_dir ?: '')

    // 3. SnpSift dbSNP annotation
    SNPSIFT_ANNOTATE(SNPEFF.out.annotated_vcf, dbsnp_vcf, output_subdir)

    // 4. Convert to table
    VARIANTS_TO_TABLE(SNPSIFT_ANNOTATE.out.annotated_vcf, output_subdir)

    emit:
    vcf            = VARDICT.out.vcf
    annotated_vcf  = SNPSIFT_ANNOTATE.out.annotated_vcf
    annotated_txt  = VARIANTS_TO_TABLE.out.table
}
