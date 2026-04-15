/*
 * QC Report Sub-workflow
 *
 * Alignment metrics, insert size, MarkDuplicates, HsMetrics,
 * on-target counts, mismatch rate
 */

include { COLLECT_ALIGNMENT_METRICS                       } from '../modules/qc_metrics'
include { MARK_DUPLICATES                                 } from '../modules/qc_metrics'
include { COLLECT_INSERT_SIZE                              } from '../modules/qc_metrics'
include { COUNT_READS                                     } from '../modules/qc_metrics'
include { BED_TO_INTERVAL_LIST                            } from '../modules/hs_metrics'
include { COLLECT_HS_METRICS as HS_METRICS_ALIGNED        } from '../modules/hs_metrics'
include { COLLECT_HS_METRICS as HS_METRICS_DEDUPED        } from '../modules/hs_metrics'
include { MISMATCH_RATE                                   } from '../modules/mismatch_rate'

workflow QC_REPORT {

    take:
    aligned_bam_ch    // tuple(sample_id, bam, bai) - first-pass aligned sorted
    deduped_bam_ch    // tuple(sample_id, bam) - deduped sorted
    genome_fasta      // path
    genome_dict       // path
    genome_fai        // path
    target_bed        // path
    blocklist         // path
    bsgenome_ref      // val

    main:

    // Prepare labeled channels for processes that handle both aligned and deduped BAMs
    aligned_labeled = aligned_bam_ch.map { sid, bam, bai -> tuple(sid, 'aligned', bam) }
    deduped_labeled = deduped_bam_ch.map { sid, bam -> tuple(sid, 'umi_deduped', bam) }

    // 1. Alignment summary metrics (both BAMs)
    COLLECT_ALIGNMENT_METRICS(
        aligned_labeled.mix(deduped_labeled),
        genome_fasta,
        genome_dict,
        genome_fai
    )

    // 2. Insert size metrics (both BAMs)
    COLLECT_INSERT_SIZE(
        aligned_labeled.mix(deduped_labeled)
    )

    // 3. MarkDuplicates (aligned BAM only)
    aligned_for_markdup = aligned_bam_ch.map { sid, bam, bai -> tuple(sid, bam) }
    MARK_DUPLICATES(aligned_for_markdup)

    // 4. On-target read counts (both BAMs)
    COUNT_READS(
        aligned_labeled.mix(deduped_labeled),
        genome_fasta,
        genome_dict,
        genome_fai,
        target_bed
    )

    // 5. BED to interval list (once per sample, using target BED)
    sample_ids_ch = aligned_bam_ch.map { sid, bam, bai -> sid }
    BED_TO_INTERVAL_LIST(sample_ids_ch, target_bed, genome_dict)

    // 6. HsMetrics - aligned
    hs_aligned_input = aligned_bam_ch
        .join(BED_TO_INTERVAL_LIST.out.interval_list)
        .map { sid, bam, bai, ilist -> tuple(sid, 'aligned', bam, ilist) }

    HS_METRICS_ALIGNED(hs_aligned_input, genome_fasta, genome_dict, genome_fai)

    // 7. HsMetrics - deduped
    hs_deduped_input = deduped_bam_ch
        .join(BED_TO_INTERVAL_LIST.out.interval_list)
        .map { sid, bam, ilist -> tuple(sid, 'umi_deduped', bam, ilist) }

    HS_METRICS_DEDUPED(hs_deduped_input, genome_fasta, genome_dict, genome_fai)

    // 8. Mismatch rate (deduped BAM)
    MISMATCH_RATE(deduped_bam_ch, target_bed, blocklist, bsgenome_ref)

    emit:
    alignment_metrics = COLLECT_ALIGNMENT_METRICS.out.metrics
    insert_metrics    = COLLECT_INSERT_SIZE.out.metrics
    markdup_metrics   = MARK_DUPLICATES.out.metrics
    ontarget_counts   = COUNT_READS.out.counts
    hs_metrics_aln    = HS_METRICS_ALIGNED.out.hs_metrics
    hs_metrics_ded    = HS_METRICS_DEDUPED.out.hs_metrics
    mismatch          = MISMATCH_RATE.out.mismatch
}
