#!/usr/bin/env nextflow

/*
 * ============================================================
 *  Roche_nxt: KAPA ctDNA Analysis Pipeline (Nextflow Edition)
 * ============================================================
 *
 *  UMI-aware ctDNA variant calling pipeline:
 *    FastQC -> UMI preprocessing -> VarDict -> SnpEff/SnpSift -> QC
 *
 *  Author  : Kenneth Kwon
 *  Version : 1.0.0
 * ============================================================
 */

nextflow.enable.dsl = 2

// ── Module imports ───────────────────────────────────────────
include { FASTQC                  } from './modules/fastqc'
include { UMI_PREPROCESSING       } from './workflows/umi_preprocessing'
include { STANDARD_PREPROCESSING  } from './workflows/standard_preprocessing'
include { VARIANT_CALLING         } from './workflows/variant_calling'
include { QC_REPORT          } from './workflows/qc_report'
include { SELECT_REPORT      } from './workflows/select_report'
include { LONGITUDINAL       } from './workflows/longitudinal_wf'
include { SNPEFF             } from './modules/snpeff'
include { SNPSIFT_ANNOTATE   } from './modules/snpsift'
include { VARIANTS_TO_TABLE  } from './modules/variants_to_table'

// ── Parameter validation ─────────────────────────────────────
def validateParams() {
    if (!params.input) {
        error "ERROR: --input samplesheet.csv is required"
    }
}

// ── Main workflow ────────────────────────────────────────────
workflow {

    // Resolve genome-specific params (moved from config for v2 parser compatibility)
    def genome = params.genomes[params.reference] ?: params.genomes['hg38']
    def resolved_fasta  = params.genome_fasta ?: genome.fasta
    def resolved_dict   = params.genome_dict  ?: genome.dict
    def resolved_dbsnp  = params.dbsnp_vcf    ?: genome.dbsnp
    def resolved_bed    = params.target_bed   ?: genome.bed_capture

    validateParams()

    log.info """
╔══════════════════════════════════════════════════════════════╗
║        Roche_nxt: KAPA ctDNA Analysis Pipeline              ║
╚══════════════════════════════════════════════════════════════╝

  Input       : ${params.input}
  Reference   : ${params.reference}
  Genome      : ${resolved_fasta}
  Target BED  : ${resolved_bed}
  AF threshold: ${params.af_threshold}
  UMI mode    : ${params.use_umi}
  Subsample   : ${params.subsample}${params.subsample.toString() == 'true' ? " (threshold: ${params.subsample_threshold_gb}GB → target: ${params.seqtk_sample_size} reads)" : ""}
  Output dir  : ${params.outdir}
──────────────────────────────────────────────────────────────
"""

    // Reference files
    def genome_fasta  = file(resolved_fasta)
    def genome_dict   = file(resolved_dict)
    def genome_fai    = file("${resolved_fasta}.fai")
    def target_bed    = file(resolved_bed)
    def dbsnp_vcf     = file(resolved_dbsnp)
    def blocklist     = file(genome.blocklist)
    def snpeff_db     = genome.snpeff_db
    def bsgenome_ref  = genome.bsgenome

    // ── Reannotation mode: re-run SnpEff/SnpSift/VariantsToTable only ────
    // Activated when --reannotate_vcf is supplied (path to published *_vardict.vcf).
    // Skips FASTQC / PREPROCESSING / VARDICT / QC_REPORT.
    // Use after adding -canon or updating SnpEff DB without re-running VarDict.
    def reannotate = (params.reannotate_vcf != null)

    if (reannotate) {

        def sid = channel.fromPath(params.input)
            .splitCsv(header: true)
            .map { row -> row.sample_id }
            .first()

        def vcf_path = file(params.reannotate_vcf)
        def output_subdir = params.output_subdir ?: ''

        log.info "Reannotation mode: SnpEff -> SnpSift -> VariantsToTable only"
        log.info "   VarDict VCF : ${vcf_path}"

        def vardict_ch = sid.map { s -> tuple(s, vcf_path) }

        SNPEFF(vardict_ch, snpeff_db, params.snpeff_data_dir ?: '')
        SNPSIFT_ANNOTATE(SNPEFF.out.annotated_vcf, dbsnp_vcf, output_subdir)
        VARIANTS_TO_TABLE(SNPSIFT_ANNOTATE.out.annotated_vcf, output_subdir)

        return
    }

    // ── Bypass mode: use pre-computed BAM + annotated_txt ────
    // Activated when --precomputed_bam is supplied.
    // Skips FASTQC / UMI_PREPROCESSING / VARIANT_CALLING / QC_REPORT.
    // Useful when delete_intermediate removed the work dir but published
    // outputs (results/.../output/bam/ and results/.../output/variants/)
    // are still intact.
    def bypass = (params.precomputed_bam != null)

    if (bypass) {

        if (!params.run_select_reporter || !params.run_longitudinal) {
            error "ERROR: --precomputed_bam requires --run_select_reporter true --run_longitudinal true"
        }

        // Derive sample_id from the samplesheet (we still need it)
        def sid = channel.fromPath(params.input)
            .splitCsv(header: true)
            .map { row -> row.sample_id }
            .first()

        def bam_path = file(params.precomputed_bam)
        def bai_path = params.precomputed_bai
            ? file(params.precomputed_bai)
            : file("${params.precomputed_bam}.bai")
        def ann_txt_path = file(params.precomputed_ann_txt)

        final_bam_ch    = sid.map { s -> tuple(s, bam_path, bai_path) }
        annotated_txt_ch = sid.map { s -> tuple(s, ann_txt_path) }

        log.info "Bypass mode: skipping FASTQC / UMI_PREPROCESSING / VARIANT_CALLING / QC_REPORT"
        log.info "   Followup BAM : ${bam_path}"
        log.info "   Ann. TXT     : ${ann_txt_path}"

        // For SELECT_REPORTERS: use Baseline VCF + Germline BAM + Followup BAM
        // (white paper: --reporters=Baseline VCF, --germline=S2 BAM, --followup=S5 BAM)
        if (params.longitudinal_baseline_ann_txt) {
            def baseline_ann   = file(params.longitudinal_baseline_ann_txt)
            def germline_bam_f = file(params.longitudinal_germline_bam)
            def germline_bai_f = params.longitudinal_germline_bai
                ? file(params.longitudinal_germline_bai)
                : file("${params.longitudinal_germline_bam}.bai")

            select_ann_ch      = sid.map { s -> tuple(s, baseline_ann) }
            select_germline_ch = sid.map { s -> tuple(s, germline_bam_f, germline_bai_f) }
            // Followup BAM = the precomputed BAM (S5)
            select_followup_ch = final_bam_ch

            log.info "   Baseline VCF : ${baseline_ann}"
            log.info "   Germline BAM : ${germline_bam_f}"
        } else {
            select_ann_ch      = annotated_txt_ch
            select_germline_ch = final_bam_ch
            select_followup_ch = final_bam_ch
        }

        SELECT_REPORT(select_ann_ch, select_germline_ch, select_followup_ch, blocklist)

        if (genome.bed_longit) {
            LONGITUDINAL(
                final_bam_ch,
                SELECT_REPORT.out.reporters,
                file(genome.bed_longit),
                blocklist,
                bsgenome_ref
            )
        } else {
            log.warn "Longitudinal analysis skipped: bed_longit is not configured for reference '${params.reference}'"
        }

    } else {

        // BWA index files (fasta.amb, .ann, .bwt, .pac, .sa)
        def genome_idx = channel.fromPath("${genome_fasta}.*").collect()

        // Parse samplesheet
        // Format: sample_id,fastq_1,fastq_2[,reference,af_threshold]
        def samples_ch = channel.fromPath(params.input)
            .splitCsv(header: true)
            .map { row ->
                def sid = row.sample_id
                def fq1 = file(row.fastq_1)
                def fq2 = file(row.fastq_2)
                tuple(sid, fq1, fq2)
            }

        // ── 1. FastQC ────────────────────────────────────────────
        FASTQC(samples_ch)

        // ── 2. Preprocessing ─────────────────────────────────────
        // Branch on params.use_umi: UMI consensus pipeline vs standard BWA + Picard MarkDuplicates.
        // Both branches emit the same channel shapes (final_bam / aligned_bam / deduped_bam)
        // so downstream workflows are unchanged.
        if (params.use_umi.toString() == 'true') {
            log.info "UMI mode: running UMI_PREPROCESSING (read structure: ${params.umi_read_structure})"
            UMI_PREPROCESSING(samples_ch, genome_fasta, genome_dict, genome_fai, genome_idx)
            final_bam_ch   = UMI_PREPROCESSING.out.final_bam
            aligned_bam_ch = UMI_PREPROCESSING.out.aligned_bam
            deduped_bam_ch = UMI_PREPROCESSING.out.deduped_bam
        } else {
            log.info "Non-UMI mode: running STANDARD_PREPROCESSING (BWA + Picard MarkDuplicates)"
            STANDARD_PREPROCESSING(samples_ch, genome_fasta, genome_dict, genome_fai, genome_idx)
            final_bam_ch   = STANDARD_PREPROCESSING.out.final_bam
            aligned_bam_ch = STANDARD_PREPROCESSING.out.aligned_bam
            deduped_bam_ch = STANDARD_PREPROCESSING.out.deduped_bam
        }

        // ── 3. Variant Calling ───────────────────────────────────
        def output_subdir = params.output_subdir ?: ''

        VARIANT_CALLING(
            final_bam_ch,
            genome_fasta,
            genome_fai,
            target_bed,
            dbsnp_vcf,
            params.af_threshold,
            snpeff_db,
            output_subdir
        )

        // ── 4. QC Report ─────────────────────────────────────────
        QC_REPORT(
            aligned_bam_ch,
            deduped_bam_ch,
            genome_fasta,
            genome_dict,
            genome_fai,
            target_bed,
            blocklist,
            bsgenome_ref
        )

        // ── 5. Select Reporter (optional) ────────────────────────
        if (params.run_select_reporter) {

            // For Longitudinal: SELECT_REPORTERS needs Baseline VCF + Germline BAM + Followup BAM
            // (white paper: --reporters=Baseline, --germline=S2, --followup=S5)
            if (params.run_longitudinal && params.longitudinal_baseline_ann_txt) {
                def baseline_ann   = file(params.longitudinal_baseline_ann_txt)
                def germline_bam_f = file(params.longitudinal_germline_bam)
                def germline_bai_f = params.longitudinal_germline_bai
                    ? file(params.longitudinal_germline_bai)
                    : file("${params.longitudinal_germline_bam}.bai")

                select_ann_ch      = samples_ch.map { sid, fq1, fq2 -> tuple(sid, baseline_ann) }
                select_germline_ch = samples_ch.map { sid, fq1, fq2 -> tuple(sid, germline_bam_f, germline_bai_f) }
                // Followup BAM = this run's final BAM (S5)
                select_followup_ch = final_bam_ch

                log.info "Longitudinal SELECT_REPORTERS:"
                log.info "  Baseline VCF : ${baseline_ann}"
                log.info "  Germline BAM : ${germline_bam_f}"

            } else {
                // Standard (non-Longitudinal) run: use current sample's own VCF + BAM
                select_ann_ch      = VARIANT_CALLING.out.annotated_txt
                select_germline_ch = final_bam_ch
                select_followup_ch = final_bam_ch
            }

            SELECT_REPORT(select_ann_ch, select_germline_ch, select_followup_ch, blocklist)
        }

        // ── 6. Longitudinal Analysis (optional) ──────────────────
        if (params.run_longitudinal && params.run_select_reporter) {
            if (genome.bed_longit) {
                LONGITUDINAL(
                    final_bam_ch,
                    SELECT_REPORT.out.reporters,
                    file(genome.bed_longit),
                    blocklist,
                    bsgenome_ref
                )
            } else {
                log.warn "Longitudinal analysis skipped: bed_longit is not configured for reference '${params.reference}'"
            }
        }

    }

    // ── Completion handler ───────────────────────────────────
    workflow.onComplete = {
        log.info """
══════════════════════════════════════════════════════════════
  Pipeline completed at : ${workflow.complete}
  Duration              : ${workflow.duration}
  Success               : ${workflow.success}
  Work dir              : ${workflow.workDir}
  Exit status           : ${workflow.exitStatus}
══════════════════════════════════════════════════════════════
"""
    }
}
