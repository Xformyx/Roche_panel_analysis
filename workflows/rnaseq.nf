#!/usr/bin/env nextflow

/*
 * ============================================================
 *  Roche_nxt: RNAseq Analysis Pipeline
 * ============================================================
 *
 *  Standard RNA-seq analysis pipeline:
 *    1. FastQC           — raw read quality control
 *    2. fastp            — adapter trimming & quality filtering
 *    3. STAR             — splice-aware alignment (2-pass)
 *    4. samtools stats   — alignment statistics
 *    5. RSeQC            — RNA-seq specific QC metrics
 *    6. featureCounts    — gene-level expression quantification
 *    7. Expression plots — CPM/TPM distribution, top genes, PCA
 *    8. QC summary JSON  — parsed metrics for web UI
 *    9. MultiQC          — aggregate QC report
 *
 *  Samplesheet format (CSV):
 *    sample_id,fastq_1,fastq_2
 *
 *  Required parameters:
 *    --input        : path to samplesheet CSV
 *    --star_index   : path to STAR genome index directory
 *    --gtf          : path to genome annotation GTF file
 *
 *  Optional parameters:
 *    --bed12        : BED12 file for RSeQC (enables TIN, read distribution)
 *    --outdir       : output directory (default: /work_nxt/results)
 *    --reference    : genome reference name (default: hg38)
 *    --data_dir     : base data directory (default: /work_nxt_data)
 *    --max_cpus     : maximum CPUs (default: 8)
 *    --max_memory   : maximum memory in GB (default: 32)
 *    --skip_rseqc   : skip RSeQC steps (default: false)
 *    --skip_plots   : skip expression visualization plots (default: false)
 *
 *  Author  : Kenneth Kwon
 *  Version : 1.0.0
 * ============================================================
 */

nextflow.enable.dsl = 2

// ── Parameters ───────────────────────────────────────────────
params.input           = null
params.outdir          = '/work_nxt/results'
params.reference       = 'hg38'
params.data_dir        = '/work_nxt_data'
params.max_cpus        = 8
params.max_memory      = 32
params.publish_dir_mode = 'copy'

// RNA-specific references (resolved from nextflow.config genomes block or passed directly)
params.star_index      = null
params.gtf             = null
params.bed12           = null    // BED12 for RSeQC (optional)

// fastp options for RNA (shorter min-length than ctDNA)
params.fastp_options   = '-g -W 5 -q 20 -u 40 -x -3 -l 50 -c'

// Skip flags
params.skip_rseqc      = false
params.skip_tin        = false   // TIN is slow (single-threaded, ~2-4h); set true to skip
params.tin_sample_size = 5000    // subsample BED12 to N transcripts for TIN (speeds up ~10x)
params.skip_plots      = false
params.skip_fusion     = false
params.skip_deseq2     = false

// CTAT genome library for STAR-Fusion (null = skip fusion step)
params.ctat_lib        = null

// ── Module includes ──────────────────────────────────────────
include { FASTQC }              from '../modules/fastqc'
include { FASTP }               from '../modules/fastp'
include { STAR_ALIGN }          from '../modules/star_align'
include { FEATURECOUNTS }       from '../modules/featurecounts'
include { MULTIQC }             from '../modules/multiqc'
include { SAMTOOLS_FLAGSTAT;
          SAMTOOLS_STATS }      from '../modules/samtools_stats'
include { RSEQC_INFER_EXPERIMENT;
          RSEQC_READ_DISTRIBUTION;
          RSEQC_JUNCTION_SATURATION;
          RSEQC_TIN }           from '../modules/rseqc'
include { RNASEQ_PLOTS }        from '../modules/rnaseq_plots'
include { RNASEQ_INTERACTIVE_PLOTS } from '../modules/rnaseq_interactive_plots'
include { RNASEQ_MULTI_SAMPLE_PLOTS } from '../modules/rnaseq_multi_sample_plots'
include { RNASEQ_DESEQ2 }       from '../modules/rnaseq_deseq2'
include { RNASEQ_PATHWAY }      from '../modules/rnaseq_pathway'
include { RNASEQ_QC_SUMMARY }   from '../modules/rnaseq_qc_summary'
include { STAR_FUSION }         from '../modules/star_fusion'

// ── Validation ───────────────────────────────────────────────
def validateRnaParams() {
    if (!params.input)       error "ERROR: --input samplesheet.csv is required"
    if (!params.star_index)  error "ERROR: --star_index (STAR genome index directory) is required"
    if (!params.gtf)         error "ERROR: --gtf (genome annotation GTF) is required"
}

// ── Main workflow ────────────────────────────────────────────
workflow {

    validateRnaParams()

    log.info """
╔══════════════════════════════════════════════════════════════╗
║        Roche_nxt: RNAseq Analysis Pipeline  v1.0.0          ║
╚══════════════════════════════════════════════════════════════╝

  Input        : ${params.input}
  Reference    : ${params.reference}
  STAR Index   : ${params.star_index}
  GTF          : ${params.gtf}
  BED12        : ${params.bed12 ?: '(not provided — RSeQC skipped)'}
  Output dir   : ${params.outdir}
  Max CPUs     : ${params.max_cpus}
  Max Memory   : ${params.max_memory} GB
  Skip RSeQC   : ${params.skip_rseqc}
  Skip Plots   : ${params.skip_plots}
  CTAT Lib     : ${params.ctat_lib ?: '(not provided — Fusion detection skipped)'}
──────────────────────────────────────────────────────────────
"""

    // ── Resolve reference paths ──────────────────────────────
    def star_idx   = file(params.star_index)
    def gtf_file   = file(params.gtf)
    def bed12_file = params.bed12    ? file(params.bed12)    : null
    def ctat_lib   = params.ctat_lib ? file(params.ctat_lib) : null
    def run_rseqc  = !params.skip_rseqc  && (bed12_file != null)
    def run_fusion = !params.skip_fusion && (ctat_lib   != null)

    // ── Parse samplesheet ────────────────────────────────────
    def reads_ch = channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def sample_id = row.sample_id
            def r1 = file(row.fastq_1)
            def r2 = file(row.fastq_2)
            if (!r1.exists()) log.warn "WARNING: R1 FASTQ not found: ${r1}"
            if (!r2.exists()) log.warn "WARNING: R2 FASTQ not found: ${r2}"
            tuple(sample_id, r1, r2)
        }

    // ── Step 1: FastQC (raw reads) ───────────────────────────
    FASTQC(reads_ch)

    // ── Step 2: fastp (adapter trimming) ────────────────────
    FASTP(reads_ch)

    // ── Step 3: STAR alignment ───────────────────────────────
    STAR_ALIGN(FASTP.out.reads, star_idx)

    // ── Step 3b: STAR-Fusion (optional, requires CTAT library) ──────────────
    if (run_fusion) {
        STAR_FUSION(STAR_ALIGN.out.chimeric_junction, ctat_lib)
    }

    // ── Step 4: samtools stats ───────────────────────────────
    SAMTOOLS_FLAGSTAT(STAR_ALIGN.out.bam)
    SAMTOOLS_STATS(STAR_ALIGN.out.bam)

    // ── Step 5: RSeQC (RNA-seq specific QC) ─────────────────
    if (run_rseqc) {
        RSEQC_INFER_EXPERIMENT(
            STAR_ALIGN.out.bam,
            STAR_ALIGN.out.bai,
            bed12_file
        )
        RSEQC_READ_DISTRIBUTION(
            STAR_ALIGN.out.bam,
            bed12_file
        )
        RSEQC_JUNCTION_SATURATION(
            STAR_ALIGN.out.bam,
            STAR_ALIGN.out.bai,
            bed12_file
        )
        // TIN is single-threaded and slow (~2-4h for full gencode BED12).
        // Subsampled to params.tin_sample_size transcripts by default (~10-15 min).
        // Set skip_tin=true to omit entirely when turnaround time is critical.
        if (!params.skip_tin) {
            RSEQC_TIN(
                STAR_ALIGN.out.bam,
                STAR_ALIGN.out.bai,
                bed12_file
            )
        }
    }

    // ── Step 6: featureCounts (gene quantification) ──────────
    FEATURECOUNTS(STAR_ALIGN.out.bam, gtf_file)

    // ── Step 7: Expression visualization plots ───────────────
    if (!params.skip_plots) {
        RNASEQ_PLOTS(FEATURECOUNTS.out.counts, gtf_file)
        RNASEQ_INTERACTIVE_PLOTS(RNASEQ_PLOTS.out.summary)
        
        // Multi-sample plots (collect all featureCounts outputs)
        RNASEQ_MULTI_SAMPLE_PLOTS(FEATURECOUNTS.out.counts.map { sid, counts -> counts }.collect())
        
        // ── Step 7b: DESeq2 Differential Expression & Pathway Analysis ────────
        // DESeq2 requires design.csv (uploaded via web UI) AND at least 2 samples.
        // If design.csv is absent the step is skipped gracefully — no dummy file needed.
        if (!params.skip_deseq2) {
            def design_csv = file("${params.outdir}/design.csv")
            if (design_csv.exists()) {
                RNASEQ_DESEQ2(RNASEQ_MULTI_SAMPLE_PLOTS.out.combined_counts, design_csv)
                RNASEQ_PATHWAY(RNASEQ_DESEQ2.out.sig_genes)
            } else {
                log.warn "DESeq2 skipped: design.csv not found at ${params.outdir}/design.csv"
                log.warn "  Upload a design CSV via the web UI (RNA 분석결과 → DESeq2 탭) and re-run."
            }
        }
    }

    // ── Step 8: QC summary JSON (for web UI) ─────────────────
    // Join all per-sample QC outputs by sample_id
    qc_input_ch = STAR_ALIGN.out.log_final
        .join(FASTP.out.report.map { sid, json, html -> tuple(sid, json) })
        .join(FEATURECOUNTS.out.summary)
        .join(SAMTOOLS_FLAGSTAT.out.flagstat)

    RNASEQ_QC_SUMMARY(
        qc_input_ch.map { sid, star_log, fastp_json, fc_summary, flagstat ->
            tuple(sid, star_log)
        },
        qc_input_ch.map { sid, star_log, fastp_json, fc_summary, flagstat ->
            tuple(sid, fastp_json)
        },
        qc_input_ch.map { sid, star_log, fastp_json, fc_summary, flagstat ->
            tuple(sid, fc_summary)
        },
        qc_input_ch.map { sid, star_log, fastp_json, fc_summary, flagstat ->
            tuple(sid, flagstat)
        }
    )

    // ── Step 9: MultiQC aggregate report ────────────────────
    def multiqc_input = channel.empty()
    multiqc_input = multiqc_input.mix(
        FASTQC.out.zip.map { sid, zip -> zip }
    )
    multiqc_input = multiqc_input.mix(
        FASTP.out.report.map { sid, json, html -> [json, html] }.flatten()
    )
    multiqc_input = multiqc_input.mix(
        STAR_ALIGN.out.log_final.map { sid, log -> log }
    )
    multiqc_input = multiqc_input.mix(
        FEATURECOUNTS.out.summary.map { sid, summary -> summary }
    )
    multiqc_input = multiqc_input.mix(
        SAMTOOLS_STATS.out.stats.map { sid, stats -> stats }
    )

    MULTIQC(multiqc_input.collect())
}
