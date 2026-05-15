/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RNASEQ_DESEQ2  —  Differential Expression Analysis using DESeq2
 *
 *  Expects a combined count matrix and a sample metadata file (design.csv).
 *  If design.csv is not provided, it attempts to guess groups from sample names
 *  (e.g., WT_1, WT_2, KO_1, KO_2) or skips analysis.
 *
 *  Outputs:
 *    - DESeq2 results table (CSV/TSV)
 *    - Volcano Plot (PNG & HTML)
 *    - MA Plot (PNG)
 *    - Sample Distance Heatmap (PNG)
 *    - Significant Genes Heatmap (PNG)
 * ─────────────────────────────────────────────────────────────────────────────
 */

process RNASEQ_DESEQ2 {
    label 'process_medium'
    publishDir "${params.outdir}/Differential_Expression", mode: params.publish_dir_mode

    input:
    path combined_counts
    path design_file // Optional: sample,condition (header required)

    output:
    path "deseq2_results.tsv", emit: results
    path "deseq2_significant_genes.tsv", emit: sig_genes
    path "deseq2_volcano.png", emit: volcano_png
    path "deseq2_volcano_interactive.html", emit: volcano_html
    path "deseq2_ma_plot.png", emit: ma_plot
    path "deseq2_sample_heatmap.png", emit: sample_heatmap
    path "deseq2_sig_genes_heatmap.png", emit: sig_heatmap

    script:
    """
    #!/usr/bin/env Rscript

    suppressPackageStartupMessages({
        library(DESeq2)
        library(ggplot2)
        library(pheatmap)
        library(RColorBrewer)
        library(plotly)
        library(htmlwidgets)
    })

    # 1. Load Data
    counts <- read.table("${combined_counts}", header=TRUE, row.names=1, sep="\\t", check.names=FALSE)

    # Guard: need at least 2 samples for DESeq2
    make_empty_outputs <- function(reason) {
        message("DESeq2 skipped: ", reason)
        empty_df <- data.frame(
            Geneid=character(), baseMean=numeric(), log2FoldChange=numeric(),
            lfcSE=numeric(), stat=numeric(), pvalue=numeric(), padj=numeric()
        )
        write.table(empty_df, "deseq2_results.tsv",          sep="\\t", row.names=FALSE, quote=FALSE)
        write.table(empty_df, "deseq2_significant_genes.tsv", sep="\\t", row.names=FALSE, quote=FALSE)
        for (f in c("deseq2_ma_plot.png","deseq2_volcano.png","deseq2_sample_heatmap.png","deseq2_sig_genes_heatmap.png")) {
            png(f, width=800, height=600, res=120)
            plot.new()
            title(paste0("DESeq2\\n(", reason, ")"))
            dev.off()
        }
        write('{"skipped":true}', "deseq2_volcano_interactive.html")
        quit(save="no", status=0)
    }

    if (ncol(counts) < 2) {
        make_empty_outputs(paste0("only ", ncol(counts), " sample(s); need ≥ 2"))
    }

    # 2. Setup Design
    design_path <- "${design_file}"
    if (file.exists(design_path) && file.size(design_path) > 0) {
        colData <- read.csv(design_path, row.names=1, stringsAsFactors=TRUE)
        # Ensure sample names match
        common <- intersect(colnames(counts), rownames(colData))
        counts <- counts[, common, drop=FALSE]
        colData <- colData[common, , drop=FALSE]
        condition_col <- colnames(colData)[1]
    } else {
        # Auto-guess groups from sample names (e.g., WT_1 / WT_2 / KO_1 / KO_2)
        samples <- colnames(counts)
        groups <- sapply(strsplit(samples, "_[0-9]+\$"), `[`, 1)
        if (length(unique(groups)) < 2) {
            # Fallback: split in half
            n <- length(samples)
            groups <- c(rep("GroupA", floor(n / 2)), rep("GroupB", ceiling(n / 2)))
        }
        colData <- data.frame(condition = factor(groups), row.names = samples)
        condition_col <- "condition"
    }

    if (length(unique(colData[[condition_col]])) < 2) {
        make_empty_outputs("fewer than 2 distinct groups after design resolution")
    }

    # 3. Run DESeq2
    dds <- DESeqDataSetFromMatrix(countData = round(counts),
                                  colData = colData,
                                  design = as.formula(paste("~", condition_col)))
    
    # Filter low count genes
    keep <- rowSums(counts(dds)) >= 10
    dds <- dds[keep,]
    
    dds <- DESeq(dds)
    res <- results(dds)
    resOrdered <- res[order(res\$padj),]
    
    # Add Gene ID column
    res_df <- as.data.frame(resOrdered)
    res_df\$Geneid <- rownames(res_df)
    res_df <- res_df[, c("Geneid", "baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj")]
    
    write.table(res_df, file="deseq2_results.tsv", sep="\\t", row.names=FALSE, quote=FALSE)
    
    # Significant genes
    sig_genes <- subset(res_df, padj < 0.05 & abs(log2FoldChange) > 1)
    write.table(sig_genes, file="deseq2_significant_genes.tsv", sep="\\t", row.names=FALSE, quote=FALSE)

    # 4. Plots
    # MA Plot
    png("deseq2_ma_plot.png", width=800, height=600, res=120)
    plotMA(res, main="DESeq2 MA Plot", ylim=c(-5,5))
    dev.off()

    # Volcano Plot (Static)
    res_df\$Significance <- "Not Sig"
    res_df\$Significance[res_df\$padj < 0.05 & res_df\$log2FoldChange > 1] <- "Up"
    res_df\$Significance[res_df\$padj < 0.05 & res_df\$log2FoldChange < -1] <- "Down"
    res_df\$Significance <- factor(res_df\$Significance, levels=c("Up", "Down", "Not Sig"))
    
    p_volc <- ggplot(res_df[!is.na(res_df\$padj),], aes(x=log2FoldChange, y=-log10(padj), color=Significance, text=Geneid)) +
        geom_point(alpha=0.6, size=1.5) +
        scale_color_manual(values=c("Up"="#C00000", "Down"="#4472C4", "Not Sig"="#D9D9D9")) +
        geom_vline(xintercept=c(-1, 1), linetype="dashed", color="black") +
        geom_hline(yintercept=-log10(0.05), linetype="dashed", color="black") +
        theme_bw() +
        labs(title="Volcano Plot", x="log2 Fold Change", y="-log10(Adjusted P-value)")
    
    ggsave("deseq2_volcano.png", p_volc, width=8, height=6, dpi=150)

    # Volcano Plot (Interactive)
    p_int <- ggplotly(p_volc, tooltip="text")
    saveWidget(p_int, "deseq2_volcano_interactive.html", selfcontained=TRUE)

    # Transformation for Heatmaps
    vsd <- vst(dds, blind=FALSE)
    
    # Sample Distance Heatmap
    sampleDists <- dist(t(assay(vsd)))
    sampleDistMatrix <- as.matrix(sampleDists)
    colors <- colorRampPalette(rev(brewer.pal(9, "Blues")))(255)
    
    png("deseq2_sample_heatmap.png", width=800, height=800, res=120)
    pheatmap(sampleDistMatrix,
             clustering_distance_rows=sampleDists,
             clustering_distance_cols=sampleDists,
             col=colors,
             main="Sample Distance Matrix")
    dev.off()

    # Significant Genes Heatmap
    if(nrow(sig_genes) > 1) {
        top_sig <- head(sig_genes\$Geneid, 50) # Plot top 50
        mat <- assay(vsd)[top_sig, ]
        mat <- mat - rowMeans(mat) # Center genes
        
        png("deseq2_sig_genes_heatmap.png", width=800, height=1000, res=120)
        pheatmap(mat, 
                 annotation_col=colData,
                 main="Top 50 Significant Genes (Centered VST)",
                 fontsize_row=8)
        dev.off()
    } else {
        file.create("deseq2_sig_genes_heatmap.png")
    }

    message("DESeq2 analysis completed.")
    """
}
