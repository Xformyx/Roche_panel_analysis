/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RNASEQ_MULTI_SAMPLE_PLOTS  —  Multi-sample expression comparison plots
 *
 *  Generates:
 *    - Combined count matrix (all samples)
 *    - PCA plot
 *    - Sample correlation heatmap
 * ─────────────────────────────────────────────────────────────────────────────
 */
process RNASEQ_MULTI_SAMPLE_PLOTS {
    label 'process_medium'
    publishDir "${params.outdir}/MultiSample_Plots", mode: params.publish_dir_mode

    input:
    path(counts_files)

    output:
    path "combined_counts.tsv", emit: combined_counts
    path "pca_plot.png", emit: pca_plot, optional: true
    path "correlation_heatmap.png", emit: heatmap, optional: true

    script:
    """
    #!/usr/bin/env Rscript

    suppressPackageStartupMessages({
        library(ggplot2)
        library(dplyr)
        library(tidyr)
        library(pheatmap)
    })

    files <- list.files(pattern = "_counts.txt\$")
    if (length(files) < 2) {
        message("Not enough samples for multi-sample plots (need >= 2).")
        file.create("combined_counts.tsv")
        quit(save = "no", status = 0)
    }

    # 1. Combine counts
    combined_df <- NULL
    for (f in files) {
        sample_name <- sub("_counts.txt", "", f)
        df <- read.table(f, header = TRUE, sep = "\\t", comment.char = "#", stringsAsFactors = FALSE)
        # Assuming format: Geneid, Chr, Start, End, Strand, Length, Count
        count_col <- df[, c(1, ncol(df))]
        colnames(count_col) <- c("Geneid", sample_name)
        
        if (is.null(combined_df)) {
            combined_df <- count_col
        } else {
            combined_df <- merge(combined_df, count_col, by = "Geneid", all = TRUE)
        }
    }
    
    # Fill NAs with 0
    combined_df[is.na(combined_df)] <- 0
    write.table(combined_df, file = "combined_counts.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

    # Prepare matrix for PCA/Heatmap
    count_mat <- as.matrix(combined_df[, -1])
    rownames(count_mat) <- combined_df\$Geneid
    
    # Remove genes with zero counts across all samples
    count_mat <- count_mat[rowSums(count_mat) > 0, ]
    
    # Log2 transform (add pseudocount)
    log_counts <- log2(count_mat + 1)

    # 2. PCA Plot
    # Calculate variance for each gene
    gene_vars <- apply(log_counts, 1, var)
    # Select top 500 most variable genes
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:min(500, length(gene_vars))]
    pca_data <- log_counts[top_genes, ]
    
    pca_res <- prcomp(t(pca_data), scale. = TRUE)
    pca_df <- as.data.frame(pca_res\$x)
    pca_df\$Sample <- rownames(pca_df)
    
    var_explained <- round(pca_res\$sdev^2 / sum(pca_res\$sdev^2) * 100, 1)
    
    p_pca <- ggplot(pca_df, aes(x = PC1, y = PC2, label = Sample)) +
        geom_point(size = 4, color = "#4472C4", alpha = 0.8) +
        geom_text(vjust = -1, size = 3) +
        labs(title = "PCA of Top 500 Most Variable Genes",
             x = paste0("PC1 (", var_explained[1], "%)"),
             y = paste0("PC2 (", var_explained[2], "%)")) +
        theme_bw(base_size = 14) +
        theme(plot.title = element_text(face = "bold"))
    
    ggsave("pca_plot.png", p_pca, width = 8, height = 6, dpi = 150)

    # 3. Sample Correlation Heatmap
    cor_mat <- cor(log_counts, method = "pearson")
    
    png("correlation_heatmap.png", width = 800, height = 800, res = 120)
    pheatmap(cor_mat, 
             main = "Sample Correlation Heatmap (Pearson)",
             color = colorRampPalette(c("#4472C4", "white", "#C00000"))(100),
             display_numbers = TRUE,
             number_color = "black",
             fontsize_number = 10)
    dev.off()

    message("Multi-sample plots generated successfully.")
    """
}
