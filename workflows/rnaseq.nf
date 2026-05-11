#!/usr/bin/env nextflow

/*
 * ============================================================
 *  Roche_nxt: RNAseq Analysis Pipeline
 * ============================================================
 *
 *  RNA-seq expression & fusion analysis pipeline.
 *  Currently a skeleton — tools and steps TBD.
 *
 *  Author  : Kenneth Kwon
 *  Version : 0.1.0 (skeleton)
 * ============================================================
 */

nextflow.enable.dsl = 2

// ── Parameters ───────────────────────────────────────────────
params.input      = null
params.outdir     = '/work_nxt/results'
params.reference  = 'hg38'
params.data_dir   = '/work_nxt_data'
params.max_cpus   = 8
params.max_memory = 32

// ── Log pipeline info ────────────────────────────────────────
log.info """
╔══════════════════════════════════════════════════════════════╗
║        Roche_nxt: RNAseq Analysis Pipeline                  ║
╚══════════════════════════════════════════════════════════════╝

  Input       : ${params.input}
  Reference   : ${params.reference}
  Output dir  : ${params.outdir}
──────────────────────────────────────────────────────────────
"""

// ── Main workflow ────────────────────────────────────────────
workflow {

    if (!params.input) {
        error "ERROR: --input samplesheet.csv is required"
    }

    // Parse samplesheet
    Channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, file(row.fastq_1), file(row.fastq_2)) }
        .set { reads_ch }

    // TODO: implement RNAseq analysis steps
    // Suggested pipeline:
    //   1. FastQC           — raw read QC
    //   2. Trim Galore      — adapter trimming
    //   3. STAR / HISAT2    — alignment to reference transcriptome
    //   4. featureCounts    — gene expression quantification
    //   5. DESeq2 / edgeR   — differential expression (optional)
    //   6. STAR-Fusion      — fusion gene detection (optional)
    //   7. MultiQC          — aggregate QC report

    reads_ch.view { sample, r1, r2 ->
        log.info "🧬 RNAseq sample queued: ${sample} (R1: ${r1.name}, R2: ${r2.name})"
    }

    log.warn "⚠ RNAseq pipeline is not yet implemented. Sample registered successfully."
}
