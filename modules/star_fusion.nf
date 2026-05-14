/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  STAR_FUSION  —  Fusion gene detection using STAR chimeric junction output
 *
 *  Requires:
 *    - Chimeric.out.junction from STAR (--chimOutJunctionFormat 1)
 *    - CTAT genome library (https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/)
 *
 *  Outputs:
 *    fusions         : full fusion predictions TSV
 *    fusions_coding  : abridged + coding effect TSV (primary output for web UI)
 * ─────────────────────────────────────────────────────────────────────────────
 */
process STAR_FUSION {
    tag "$sample_id"
    label 'process_high'
    publishDir { "${params.outdir}/${sample_id}/star_fusion" }, mode: params.publish_dir_mode,
        saveAs: { fn -> fn }

    input:
    tuple val(sample_id), path(chimeric_junction)
    path ctat_lib

    output:
    tuple val(sample_id), path("${sample_id}_star-fusion.fusion_predictions.tsv"),                       emit: fusions
    tuple val(sample_id), path("${sample_id}_star-fusion.fusion_predictions.abridged.tsv"),              emit: fusions_abridged
    tuple val(sample_id), path("${sample_id}_star-fusion.fusion_predictions.abridged.coding_effect.tsv"), emit: fusions_coding, optional: true

    script:
    """
    # STAR-Fusion may return exit code 1 with older CTAT libraries even on success;
    # treat as success if the primary output file is produced.
    STAR-Fusion \\
        --genome_lib_dir ${ctat_lib} \\
        -J ${chimeric_junction} \\
        --output_dir ./ \\
        --CPU ${task.cpus} \\
        --examine_coding_effect \\
        --no_annotation_filter || true

    # Verify primary output was produced
    [ -f "star-fusion.fusion_predictions.tsv" ] || { echo "ERROR: STAR-Fusion output not found"; exit 1; }

    # Only rename regular files (not directories like star-fusion.preliminary)
    for f in star-fusion.*.tsv star-fusion.*.txt; do
        [ -f "\$f" ] && mv "\$f" "${sample_id}_\$f" || true
    done
    """
}
