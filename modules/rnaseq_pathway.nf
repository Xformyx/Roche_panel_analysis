/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RNASEQ_PATHWAY  —  GO and KEGG Pathway Enrichment Analysis
 *
 *  Uses clusterProfiler to perform enrichment analysis on significant genes
 *  from DESeq2 output.
 *
 *  Outputs:
 *    - GO enrichment results (TSV) & Dotplot (PNG)
 *    - KEGG enrichment results (TSV) & Dotplot (PNG)
 * ─────────────────────────────────────────────────────────────────────────────
 */

process RNASEQ_PATHWAY {
    label 'process_medium'
    publishDir "${params.outdir}/Pathway_Analysis", mode: params.publish_dir_mode

    input:
    path sig_genes_tsv

    output:
    path "go_enrichment.tsv", emit: go_res, optional: true
    path "go_dotplot.png", emit: go_plot, optional: true
    path "kegg_enrichment.tsv", emit: kegg_res, optional: true
    path "kegg_dotplot.png", emit: kegg_plot, optional: true

    script:
    """
    #!/usr/bin/env Rscript

    suppressPackageStartupMessages({
        library(clusterProfiler)
        library(org.Hs.eg.db)
        library(ggplot2)
        library(enrichplot)
    })

    # 1. Load significant genes
    sig_df <- read.table("${sig_genes_tsv}", header=TRUE, sep="\\t", stringsAsFactors=FALSE)
    
    if (nrow(sig_df) < 5) {
        message("Too few significant genes (<5) for pathway analysis.")
        file.create("go_enrichment.tsv")
        file.create("kegg_enrichment.tsv")
        quit(save="no", status=0)
    }

    # Strip version numbers from Ensembl IDs (e.g., ENSG00000141510.11 -> ENSG00000141510)
    gene_ids <- sub("\\\\.[0-9]+\$", "", sig_df\$Geneid)

    # Convert Ensembl to Entrez ID
    gene_map <- bitr(gene_ids, fromType="ENSEMBL", toType="ENTREZID", OrgDb=org.Hs.eg.db)
    entrez_ids <- gene_map\$ENTREZID

    if (length(entrez_ids) == 0) {
        message("Failed to map genes to Entrez IDs.")
        file.create("go_enrichment.tsv")
        file.create("kegg_enrichment.tsv")
        quit(save="no", status=0)
    }

    # 2. GO Enrichment Analysis (Biological Process)
    ego <- enrichGO(gene          = entrez_ids,
                    OrgDb         = org.Hs.eg.db,
                    ont           = "BP",
                    pAdjustMethod = "BH",
                    pvalueCutoff  = 0.05,
                    qvalueCutoff  = 0.2,
                    readable      = TRUE)

    if (!is.null(ego) && nrow(ego) > 0) {
        write.table(as.data.frame(ego), file="go_enrichment.tsv", sep="\\t", row.names=FALSE, quote=FALSE)
        
        png("go_dotplot.png", width=800, height=600, res=120)
        print(dotplot(ego, showCategory=20, title="GO Biological Process Enrichment"))
        dev.off()
    } else {
        file.create("go_enrichment.tsv")
    }

    # 3. KEGG Pathway Enrichment Analysis
    kk <- enrichKEGG(gene         = entrez_ids,
                     organism     = 'hsa',
                     pvalueCutoff = 0.05)

    if (!is.null(kk) && nrow(kk) > 0) {
        # Convert Entrez IDs back to symbols for readability in output
        kk <- setReadable(kk, OrgDb = org.Hs.eg.db, keyType="ENTREZID")
        write.table(as.data.frame(kk), file="kegg_enrichment.tsv", sep="\\t", row.names=FALSE, quote=FALSE)
        
        png("kegg_dotplot.png", width=800, height=600, res=120)
        print(dotplot(kk, showCategory=20, title="KEGG Pathway Enrichment"))
        dev.off()
    } else {
        file.create("kegg_enrichment.tsv")
    }

    message("Pathway analysis completed.")
    """
}
