# Fresh R process replay from the external imputation checkpoint; no new imputations.
args<-commandArgs(trailingOnly=TRUE)
.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages({library(survey);library(mice);library(splines)})
options(survey.lonely.psu='fail')
for(e in parse('R/analysis.R')) {
  if(is.call(e) && identical(e[[1]],as.name('<-')) && is.call(e[[3]]) &&
     identical(e[[3]][[1]],as.name('function'))) eval(e)
}
root<-normalizePath(args[1]);out<-file.path(root,'derived/v03')
d<-read.csv(file.path(out,'persons.csv'),na.strings=c('','NA'))
for(v in c('ra_unknown_type','ra_conflict','no_arthritis','asthma_conflict','smoke_conflict'))
  d[[v]]<-tolower(as.character(d[[v]]))=='true'
saved<-readRDS(file.path(out,'imputations.rds'));imp<-saved$imp;ix<-saved$index
knots<-saved$age_knots;covariates<-c('age','sex','race','education','pir','smoke')
fits<-lapply(seq_len(imp$m),function(i){
  x<-d;z<-complete(imp,i)
  for(v in c('education','pir','smoke'))x[ix,v]<-as.numeric(as.character(z[[v]]))
  fit_one(design_for(x,seq(2001,2017,2)),'M2')
})
new<-pool_scalar(sapply(fits,`[[`,'q'),sapply(fits,`[[`,'u'),min(sapply(fits,`[[`,'df')),TRUE)
old<-read.csv('results/tables/association_models.csv')
old<-old[old$analysis=='primary_MI' & old$model=='M2',]
fields<-c('estimate','lower','upper','log_or','std_error','df')
error<-max(abs(unlist(new[fields])-unlist(old[fields])))
stopifnot(error<1e-10)
jsonlite::write_json(list(verdict='pass',check='fresh_R_process_primary_M2_replay',
                         max_absolute_error=error,imputations=imp$m,
                         limitation='Same locked environment and saved imputation checkpoint; not an independent machine or fresh imputation rerun.'),
                    'results/qc/replay_primary.json',auto_unbox=TRUE,pretty=TRUE)
cat('PASS: fresh-session primary replay; maximum numerical difference',error,'\n')
