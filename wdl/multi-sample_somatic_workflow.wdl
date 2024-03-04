version development

import "patient.wdl" as p
import "patient.define.wdl" as p_def
import "workflow_arguments.wdl" as wfargs
import "workflow_resources.wdl" as wfres
import "runtime_collection.wdl" as rtc
import "tasks.wdl"
import "cnv_workflow.wdl" as cnv
import "snv_workflow.wdl" as snv
#import "clonal_decomposition.wdl" as cd
#import "calculate_tumor_mutation_burden.wdl" as tmb


workflow MultiSampleSomaticWorkflow {
    input {
        # todo: add options for inputting cached output

        Patient patient = GetPatient.patient

        String individual_id
        Array[String]? tumor_sample_names
        Array[File]+ tumor_bams
        Array[File]+ tumor_bais
        Array[File]+ tumor_target_intervals
        Array[File]? tumor_annotated_target_intervals
        Array[File]? tumor_cnv_panel_of_normals
        Array[String]? normal_sample_names
        Array[File]? normal_bams
        Array[File]? normal_bais
        Array[File]? normal_target_intervals
        Array[File]? normal_annotated_target_intervals
        Array[File]? normal_cnv_panel_of_normals

        Int scatter_count = 10

        WorkflowArguments args = Parameters.arguments
        WorkflowResources resources = Files.resources
        RuntimeCollection runtime_collection = RuntimeParameters.rtc
    }

    call rtc.DefineRuntimeCollection as RuntimeParameters {
        input:
            num_bams = length(tumor_bams) + length(select_first([normal_bams, []])),
            scatter_count = scatter_count,
    }

    call wfres.DefineWorkflowResources as Files {}

    call wfargs.DefineWorkflowArguments as Parameters {
        input:
            scatter_count = scatter_count,
            resources = resources,
            runtime_collection = runtime_collection,
    }

    call p_def.DefinePatient as GetPatient {
        input:
            individual_id = individual_id,

            tumor_sample_names = tumor_sample_names,
            tumor_bams = tumor_bams,
            tumor_bais = tumor_bais,
            tumor_target_intervals = tumor_target_intervals,
            tumor_annotated_target_intervals = tumor_annotated_target_intervals,
            tumor_cnv_panel_of_normals = tumor_cnv_panel_of_normals,

            normal_sample_names = normal_sample_names,
            normal_bams = normal_bams,
            normal_bais = normal_bais,
            normal_target_intervals = normal_target_intervals,
            normal_annotated_target_intervals = normal_annotated_target_intervals,
            normal_cnv_panel_of_normals = normal_cnv_panel_of_normals,

            runtime_collection = runtime_collection,
    }

    call cnv.CNVWorkflow {
        input:
            args = args,
            patient = patient,
            runtime_collection = runtime_collection,
    }

    call snv.SNVWorkflow {
        input:
            args = args,
            patient = CNVWorkflow.updated_patient,
            runtime_collection = runtime_collection,
    }

#    call cd.ClonalDecomposition {
#
#    }

#    call tmb.CalculateTumorMutationBurden as TMB {
#
#    }

    output {
#        Array[File]? covered_regions_bed = TMB.regions_bed
#        Array[File?]? covered_regions_bam = TMB.regions_bam
#        Array[File?]? covered_regions_bai = TMB.regions_bai
#        Array[File?]? covered_regions_interval_list = TMB.regions_interval_list

        File? unfiltered_vcf = SNVWorkflow.unfiltered_vcf
        File? unfiltered_vcf_idx = SNVWorkflow.unfiltered_vcf_idx
        File? mutect_stats = SNVWorkflow.mutect_stats
        File? bam = SNVWorkflow.bam
        File? bai = SNVWorkflow.bai
        File? orientation_bias = SNVWorkflow.orientation_bias
        File? filtered_vcf = SNVWorkflow.filtered_vcf
        File? filtered_vcf_idx = SNVWorkflow.filtered_vcf_idx
        File? somatic_vcf = SNVWorkflow.somatic_vcf
        File? somatic_vcf_idx = SNVWorkflow.somatic_vcf_idx
        File? germline_vcf = SNVWorkflow.germline_vcf
        File? germline_vcf_idx = SNVWorkflow.germline_vcf_idx
        File? filtering_stats = SNVWorkflow.filtering_stats
        Array[File?]? called_germline_allelic_counts = SNVWorkflow.called_germline_allelic_counts
        Array[File?]? called_somatic_allelic_counts = SNVWorkflow.called_somatic_allelic_counts
        Array[File]? annotated_variants = SNVWorkflow.annotated_variants
        Array[File?]? annotated_variants_idx = SNVWorkflow.annotated_variants_idx

        File? genotyped_snparray_vcf = CNVWorkflow.genotyped_snparray_vcf
        File? genotyped_snparray_vcf_idx = CNVWorkflow.genotyped_snparray_vcf_idx
        File? snparray_ref_counts = CNVWorkflow.snparray_ref_counts
        File? snparray_alt_counts = CNVWorkflow.snparray_alt_counts
        File? snparray_other_alt_counts = CNVWorkflow.snparray_other_alt_counts
        File? sample_snp_correlation = CNVWorkflow.sample_snp_correlation
        Array[File]? sample_snparray_genotype_likelihoods = CNVWorkflow.sample_snparray_genotype_likelihoods
        Array[File]? snparray_pileups = CNVWorkflow.snparray_pileups
        Array[File]? snparray_allelic_counts = CNVWorkflow.snparray_allelic_counts
        Array[File]? contamination_table = CNVWorkflow.contamination_tables
        Array[File]? segmentation_table = CNVWorkflow.segmentation_tables
        Array[File?]? target_read_counts = CNVWorkflow.target_read_counts
        Array[File?]? denoised_copy_ratios = CNVWorkflow.denoised_copy_ratios

        File? modeled_segments = CNVWorkflow.modeled_segments
        Array[File]? cr_segments = CNVWorkflow.cr_segments
        Array[File]? called_cr_segments = CNVWorkflow.called_cr_segments
        Array[File]? af_model_parameters = CNVWorkflow.af_model_parameters
        Array[File]? cr_model_parameters = CNVWorkflow.cr_model_parameters
    }
}
