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
include { FASTQC             } from './modules/fastqc'
include { UMI_PREPROCESSING  } from './workflows/umi_preprocessing'
include { VARIANT_CALLING    } from './workflows/variant_calling'
include { QC_REPORT          } from './workflows/qc_report'
include { SELECT_REPORT      } from './workflows/select_report'
include { LONGITUDINAL       } from './workflows/longitudinal_wf'

// ── Parameter validation ─────────────────────────────────────
def validateParams() {
    if (!params.input) {
        error "ERROR: --input samplesheet.csv is required"
    }
    if (!file(params.genome_fasta).exists()) {
        log.warn "Reference genome not found at: ${params.genome_fasta}"
    }
}

// ── Helper: collect BWA index files alongside the FASTA ──────
def getBwaIndex(fasta) {
    def fasta_file = file(fasta)
    def parent = fasta_file.parent
    def base = fasta_file.name
    return Channel.fromPath("${parent}/${base}.*")
        .collect()
}

// ── Log pipeline info ────────────────────────────────────────
log.info """
╔══════════════════════════════════════════════════════════════╗
║        Roche_nxt: KAPA ctDNA Analysis Pipeline              ║
╚══════════════════════════════════════════════════════════════╝

  Input       : ${params.input}
  Reference   : ${params.reference}
  Genome      : ${params.genome_fasta}
  Target BED  : ${params.target_bed}
  AF threshold: ${params.af_threshold}
  Output dir  : ${params.outdir}
──────────────────────────────────────────────────────────────
"""

// ── Main workflow ────────────────────────────────────────────
workflow {

    validateParams()

    // Resolve genome config
    def genome = params.genomes[params.reference]

    // Reference files
    genome_fasta  = file(params.genome_fasta)
    genome_dict   = file(params.genome_dict)
    genome_fai    = file("${params.genome_fasta}.fai")
    target_bed    = file(params.target_bed)
    dbsnp_vcf     = file(params.dbsnp_vcf)
    blocklist     = file(genome.blocklist)
    snpeff_db     = genome.snpeff_db
    bsgenome_ref  = genome.bsgenome

    // BWA index files (fasta.amb, .ann, .bwt, .pac, .sa)
    genome_idx = Channel.fromPath("${genome_fasta}.*").collect()

    // Parse samplesheet
    // Format: sample_id,fastq_1,fastq_2[,reference,af_threshold]
    samples_ch = Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def sid = row.sample_id
            def fq1 = file(row.fastq_1)
            def fq2 = file(row.fastq_2)
            tuple(sid, fq1, fq2)
        }

    // ── 1. FastQC ────────────────────────────────────────────
    FASTQC(samples_ch)

    // ── 2. UMI Preprocessing ─────────────────────────────────
    UMI_PREPROCESSING(samples_ch, genome_fasta, genome_dict, genome_fai, genome_idx)

    final_bam_ch   = UMI_PREPROCESSING.out.final_bam
    aligned_bam_ch = UMI_PREPROCESSING.out.aligned_bam
    deduped_bam_ch = UMI_PREPROCESSING.out.deduped_bam

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
        SELECT_REPORT(
            VARIANT_CALLING.out.annotated_txt,
            final_bam_ch,
            target_bed
        )
    }

    // ── 6. Longitudinal Analysis (optional) ──────────────────
    if (params.run_longitudinal && params.run_select_reporter) {
        LONGITUDINAL(
            final_bam_ch,
            SELECT_REPORT.out.reporters,
            file(genome.bed_longit),
            blocklist
        )
    }
}

// ── Completion handler ───────────────────────────────────────
workflow.onComplete {
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
