/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RNASEQ_PLOTS  —  Expression quantification plots & summary statistics
 *
 *  Generates:
 *    - Count distribution (log2 CPM density plot)
 *    - Top expressed genes bar chart
 *    - PCA plot (if multiple samples)
 *    - Sample correlation heatmap (if multiple samples)
 *    - Biotype composition pie chart
 *    - Summary expression table (TPM / CPM)
 * ─────────────────────────────────────────────────────────────────────────────
 */
process RNASEQ_PLOTS {
    tag "$sample_id"
    label 'process_medium'
    publishDir "${params.outdir}/${sample_id}/expression_plots", mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(counts)
    path gtf

    output:
    tuple val(sample_id), path("${sample_id}_expression_summary.tsv"), emit: summary
    tuple val(sample_id), path("${sample_id}_*.png"),                   emit: plots

    script:
    """
    #!/usr/bin/env Rscript

    suppressPackageStartupMessages({
        library(ggplot2)
        library(dplyr)
        library(tidyr)
        library(scales)
    })

    sample_id <- "${sample_id}"

    # ── 1. Load featureCounts output ──────────────────────────────────────────
    cnt_raw <- read.table("${counts}", header=TRUE, sep="\\t", comment.char="#",
                          stringsAsFactors=FALSE)

    # Column names: Geneid, Chr, Start, End, Strand, Length, <BAM_path>
    gene_ids  <- cnt_raw[["Geneid"]]
    lengths   <- cnt_raw[["Length"]]
    count_col <- cnt_raw[, ncol(cnt_raw)]

    counts_df <- data.frame(
        gene_id = gene_ids,
        length  = lengths,
        count   = count_col,
        stringsAsFactors = FALSE
    )

    # ── 2. Compute CPM & TPM ─────────────────────────────────────────────────
    total_counts <- sum(counts_df\$count)
    counts_df\$CPM <- (counts_df\$count / total_counts) * 1e6

    rpk <- counts_df\$count / (counts_df\$length / 1000)
    scale_factor <- sum(rpk) / 1e6
    counts_df\$TPM <- rpk / scale_factor

    counts_df\$log2CPM <- log2(counts_df\$CPM + 1)

    # ── 3. Summary table ─────────────────────────────────────────────────────
    summary_df <- counts_df[order(-counts_df\$count), ]
    write.table(summary_df, file=paste0(sample_id, "_expression_summary.tsv"),
                sep="\\t", row.names=FALSE, quote=FALSE)

    # ── 4. Plot: Count distribution (log2 CPM density) ───────────────────────
    expressed <- counts_df[counts_df\$count > 0, ]
    p_density <- ggplot(expressed, aes(x=log2CPM)) +
        geom_histogram(bins=80, fill="#4472C4", color="white", alpha=0.85) +
        geom_vline(xintercept=log2(1+1), linetype="dashed", color="red", linewidth=0.8) +
        labs(title=paste0(sample_id, " — Read Count Distribution"),
             subtitle=paste0("Total genes: ", nrow(counts_df),
                             "  |  Expressed (count>0): ", nrow(expressed)),
             x="log2(CPM + 1)", y="Number of Genes") +
        theme_bw(base_size=13) +
        theme(plot.title=element_text(face="bold"))
    ggsave(paste0(sample_id, "_count_distribution.png"), p_density,
           width=8, height=5, dpi=150)

    # ── 5. Plot: Top 30 expressed genes (TPM) ────────────────────────────────
    top30 <- head(counts_df[order(-counts_df\$TPM), ], 30)
    top30\$gene_id <- factor(top30\$gene_id, levels=rev(top30\$gene_id))
    p_top <- ggplot(top30, aes(x=gene_id, y=TPM)) +
        geom_bar(stat="identity", fill="#ED7D31", alpha=0.9) +
        coord_flip() +
        labs(title=paste0(sample_id, " — Top 30 Expressed Genes (TPM)"),
             x=NULL, y="TPM") +
        theme_bw(base_size=12) +
        theme(plot.title=element_text(face="bold"))
    ggsave(paste0(sample_id, "_top30_genes.png"), p_top,
           width=9, height=7, dpi=150)

    # ── 6. Plot: Expression level categories (pie) ───────────────────────────
    cats <- data.frame(
        Category = c("Not expressed (0)", "Low (CPM 0-1)", "Medium (CPM 1-10)",
                     "High (CPM 10-100)", "Very High (CPM >100)"),
        Count = c(
            sum(counts_df\$count == 0),
            sum(counts_df\$CPM > 0 & counts_df\$CPM <= 1),
            sum(counts_df\$CPM > 1  & counts_df\$CPM <= 10),
            sum(counts_df\$CPM > 10 & counts_df\$CPM <= 100),
            sum(counts_df\$CPM > 100)
        )
    )
    cats\$Pct <- round(cats\$Count / sum(cats\$Count) * 100, 1)
    cats\$Label <- paste0(cats\$Category, "\\n(", cats\$Pct, "%)")
    palette5 <- c("#D9D9D9","#9DC3E6","#4472C4","#ED7D31","#C00000")
    p_pie <- ggplot(cats, aes(x="", y=Count, fill=Category)) +
        geom_bar(stat="identity", width=1, color="white") +
        coord_polar("y") +
        scale_fill_manual(values=palette5) +
        labs(title=paste0(sample_id, " — Gene Expression Categories"),
             fill="Category") +
        theme_void(base_size=12) +
        theme(plot.title=element_text(face="bold", hjust=0.5),
              legend.position="right")
    ggsave(paste0(sample_id, "_expression_categories.png"), p_pie,
           width=9, height=6, dpi=150)

    # ── 7. Plot: Cumulative expression (top N genes cover X% of reads) ───────
    sorted_tpm <- sort(counts_df\$TPM, decreasing=TRUE)
    cumsum_pct <- cumsum(sorted_tpm) / sum(sorted_tpm) * 100
    cum_df <- data.frame(
        rank = seq_along(cumsum_pct),
        cum_pct = cumsum_pct
    )
    p_cum <- ggplot(cum_df[cum_df\$rank <= 5000, ], aes(x=rank, y=cum_pct)) +
        geom_line(color="#4472C4", linewidth=1) +
        geom_hline(yintercept=c(50,80,90), linetype="dashed",
                   color=c("#ED7D31","#C00000","#7030A0"), linewidth=0.7) +
        labs(title=paste0(sample_id, " — Cumulative Expression (Top Genes)"),
             x="Number of Genes (ranked by TPM)", y="Cumulative % of Total TPM") +
        theme_bw(base_size=13) +
        theme(plot.title=element_text(face="bold"))
    ggsave(paste0(sample_id, "_cumulative_expression.png"), p_cum,
           width=8, height=5, dpi=150)

    message("Expression plots generated for ", sample_id)
    """
}
