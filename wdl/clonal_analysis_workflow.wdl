version development

import "sample.wdl" as s
import "patient.wdl" as p
import "patient.update_samples.wdl" as p_update_s
import "workflow_arguments.wdl" as wfargs
import "runtime_collection.wdl" as rtc
import "absolute.wdl" as abs


workflow ClonalAnalysisWorkflow {
    input {
        Patient patient
        WorkflowArguments args
        RuntimeCollection runtime_collection
    }

#    if (args.run_clonal_decomposition) {
#        scatter (sample in patient.samples) {
#            if (defined(sample.copy_ratio_segmentation) && defined(sample.af_model_parameters) && defined(sample.annotated_variants)) {
#                call abs.Absolute {
#                    input:
#                        acs_conversion_script = args.acs_conversion_script,
#                        sample_name = sample.name,
#                        copy_ratio_segmentation = select_first([sample.copy_ratio_segmentation]),
#                        af_model_parameters = select_first([sample.af_model_parameters]),
#                        annotated_variants = select_first([sample.annotated_variants]),
#                        runtime_collection = runtime_collection
#                }
#            }
#        }
#        Array[File] plots = select_all(Absolute.plot)
#        Array[File] rdata = select_all(Absolute.rdata)
#    }

    scatter (sample in patient.samples) {
        call abs.Absolute {
            input:
                acs_conversion_script = args.acs_conversion_script,
                sample_name = sample.name,
                copy_ratio_segmentation = select_first([sample.copy_ratio_segmentation]),
                af_model_parameters = select_first([sample.af_model_parameters]),
                annotated_variants = select_first([sample.annotated_variants]),
                runtime_collection = runtime_collection
        }
    }
    Array[File] plots = select_all(Absolute.plot)
    Array[File] rdata = select_all(Absolute.rdata)

    # phylogicNDT

    output {
        Array[File]? absolute_plots = plots
        Array[File]? absolute_rdata = rdata
    }
}