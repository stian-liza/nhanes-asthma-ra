# Fresh-run ingestion and phenotype audit. All participant-level products stay external.
.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib', .libPaths()))
suppressPackageStartupMessages({library(haven); library(dplyr); library(jsonlite)})
root <- '/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1'
out <- 'outputs/year_extension_20261008_v01'
stopifnot(dir.exists(root))
write <- function(x,name) write.csv(x,file.path(out,paste0(name,'.csv')),row.names=FALSE,na='')
dict <- read.csv(file.path(out,'variable_dictionary.csv'))
expected <- read.csv(file.path(out,'official_frequencies.csv'), colClasses=c(code='character'))
checks <- joins <- bmi_qc <- list(); cycles <- list()
catalog <- read.csv(file.path(out,'cycle_catalog.csv'),na.strings=NULL)
for (ci in seq_len(nrow(catalog))) {
  cyc<-catalog[ci,];year<-cyc$year;idx<-cyc$survey_code;suffix<-cyc$suffix;prefix<-cyc$prefix
  modules <- list()
  for (mod in c('DEMO','MCQ','SMQ','BMX')) {
    path <- file.path(root,'data',year,paste0(prefix,mod,suffix,'.xpt'))
    x <- as.data.frame(read_xpt(path)); names(x)<-toupper(names(x))
    stopifnot(!anyNA(x$SEQN),!anyDuplicated(x$SEQN))
    req <- dict[dict$year==year & dict$module==mod,'variable']
    stopifnot(all(req %in% names(x)))
    for(v in req) {
      ex <- expected[expected$year==year & expected$module==mod & expected$variable==v,]
      for(j in seq_len(nrow(ex))) {
        code <- ex$code[j]; z<-as.numeric(x[[v]])
        if(code=='.') n<-sum(is.na(z))
        else if(grepl(' to ',code,fixed=TRUE)) {
          bounds<-as.numeric(strsplit(code,' to ',fixed=TRUE)[[1]])
          # Codebook weight range endpoints are rounded display values. This
          # tolerance changes only frequency validation, never participant weights.
          tol<-if(grepl('^WTMEC',v)) 0.0000051 else 1e-12
          n<-sum(z>=bounds[1]-tol & z<=bounds[2]+tol,na.rm=TRUE)
        } else {value<-suppressWarnings(as.numeric(code));stopifnot(!is.na(value));n<-sum(z==value,na.rm=TRUE)}
        checks[[length(checks)+1]]<-data.frame(year,module=mod,variable=v,code,expected=ex$count[j],observed=n,pass=n==ex$count[j])
      }
    }
    keep<-req
    if(mod=='BMX') keep<-union(keep,intersect(c('BMXWT','BMXHT','BMIWT','BMIHT','BMDSTATS','BMAEXSTS','BMXSTATS'),names(x)))
    x<-x[,keep,drop=FALSE];x[]<-lapply(x,as.numeric)
    x[[paste0('matched_',mod)]]<-TRUE
    modules[[mod]]<-x
  }
  base<-modules$DEMO; stopifnot(all(base$SDDSRVYR==idx))
  for(mod in c('MCQ','SMQ','BMX')) {
    x<-modules[[mod]];before<-nrow(base)
    joins[[length(joins)+1]]<-data.frame(year,module=mod,demo_n=before,module_n=nrow(x),matched=sum(base$SEQN %in% x$SEQN),unmatched_demo=sum(!base$SEQN %in% x$SEQN),orphan_module=sum(!x$SEQN %in% base$SEQN),duplicate_ids=anyDuplicated(x$SEQN))
    stopifnot(all(x$SEQN %in% base$SEQN))
    base<-left_join(base,x,by='SEQN',relationship='one-to-one');stopifnot(nrow(base)==before)
  }
  typevar<-if(year<2009)'MCQ190' else if(year==2009)'MCQ191' else 'MCQ195'
  base$arthritis_type<-base[[typevar]];base$ra_code<-if(year<2011)1 else 2
  base$official_mec_weight<-base[[cyc$weight]]
  base$analysis_weight<-base$official_mec_weight*cyc$duration/23.2
  base$cycle_label<-cyc$label
  base$year<-year
  ok<-with(base,is.finite(BMXBMI)&is.finite(BMXWT)&is.finite(BMXHT)&BMXHT>0)
  delta<-with(base,abs(BMXBMI-BMXWT/(BMXHT/100)^2))
  bmi_qc[[length(bmi_qc)+1]]<-data.frame(year,n_bmi=sum(is.finite(base$BMXBMI)),n_height_weight=sum(ok),max_rounding_difference=max(delta[ok]),n_discrepancy_gt_0_11=sum(delta[ok]>.11),min_bmi=min(base$BMXBMI,na.rm=TRUE),max_bmi=max(base$BMXBMI,na.rm=TRUE))
  cycles[[length(cycles)+1]]<-base
  cat('Read and joined',year,nrow(base),'records\n')
}
checks<-bind_rows(checks);write(checks,'official_frequency_checks');write(bind_rows(joins),'join_checks');write(bind_rows(bmi_qc),'bmi_qc')
stopifnot(all(checks$pass))
d<-bind_rows(cycles);stopifnot(!anyDuplicated(d$SEQN))
# Distinct reasons are retained even outside the analysis domain.
status_yesno <- function(x, matched, age, minage) case_when(
  age<minage ~ 'not_asked_age', is.na(matched) ~ 'module_unmatched',
  x==1 ~ 'yes',x==2 ~ 'no',x==7 ~ 'refused',x==9 ~ 'dont_know',
  is.na(x) ~ 'actual_missing',TRUE ~ 'invalid_code')
d$asthma_status<-status_yesno(d$MCQ010,d$matched_MCQ,d$RIDAGEYR,1)
d$asthma<-case_when(d$asthma_status=='yes'~1,d$asthma_status=='no'~0,TRUE~NA_real_)
a<-d$MCQ160A;t<-d$arthritis_type
other<-(!is.na(t)) & ((d$year<2009 & t %in% c(2,3)) | (d$year==2009 & t %in% c(2,3,4)) | (d$year>=2011 & t %in% c(1,3,4)))
d$arthritis_status<-case_when(
 d$RIDAGEYR<20 ~ 'not_asked_age',is.na(d$matched_MCQ) ~ 'module_unmatched',
 a %in% c(2,7,9) & !is.na(t) ~ 'logic_conflict',is.na(a)&!is.na(t) ~ 'logic_conflict',
 a==2 ~ 'no_arthritis',a==7 ~ 'arthritis_refused',a==9 ~ 'arthritis_dont_know',is.na(a) ~ 'arthritis_missing',
 a==1 & t==d$ra_code ~ 'RA',a==1 & other ~ 'other_known_arthritis',
 a==1 & t==7 ~ 'type_refused',a==1 & t==9 ~ 'type_dont_know',a==1 & is.na(t) ~ 'type_missing',TRUE~'invalid_code')
d$ra<-case_when(d$arthritis_status=='RA'~1,d$arthritis_status=='no_arthritis'~0,TRUE~NA_real_)
s<-d$SMQ020;now<-d$SMQ040
d$smoke_status<-case_when(
 d$RIDAGEYR<ifelse(d$year<2013,20,18) ~ 'not_asked_age',is.na(d$matched_SMQ) ~ 'module_unmatched',
 s %in% c(2,7,9)&!is.na(now) ~ 'logic_conflict',is.na(s)&!is.na(now) ~ 'logic_conflict',
 s==2 ~ 'never',s==1 & now==3 ~ 'former',s==1 & now %in% c(1,2) ~ 'current',
 s==7 ~ 'lifetime_refused',s==9 ~ 'lifetime_dont_know',is.na(s) ~ 'lifetime_missing',
 s==1 & now==7 ~ 'current_refused',s==1 & now==9 ~ 'current_dont_know',s==1 & is.na(now) ~ 'current_missing',TRUE~'invalid_code')
d$smoking<-factor(ifelse(d$smoke_status %in% c('never','former','current'),d$smoke_status,NA),levels=c('never','former','current'))
d$age<-d$RIDAGEYR
d$sex<-factor(d$RIAGENDR,levels=1:2,labels=c('Male','Female'))
d$race<-factor(d$RIDRETH1,levels=c(3,1,2,4,5),labels=c('NH_White','Mexican','Other_Hispanic','NH_Black','Other_Multiracial'))
d$education<-factor(d$DMDEDUC2,levels=c(5,1,2,3,4),labels=c('College_grad','Less_than_9th','9th_11th','High_school','Some_college'))
d$pir<-ifelse(is.finite(d$INDFMPIR)&d$INDFMPIR>=0&d$INDFMPIR<=5,d$INDFMPIR,NA)
d$bmi<-ifelse(is.finite(d$BMXBMI)&d$BMXBMI>0,d$BMXBMI,NA)
d$agegroup<-cut(d$age,c(20,40,60,80),right=FALSE,labels=c('20-39','40-59','60-79'))
d$bmigroup<-cut(d$bmi,c(0,18.5,25,30,Inf),right=FALSE,labels=c('Underweight','Normal','Overweight','Obese'))
d$pirgroup<-factor(ifelse(is.na(d$pir),NA,ifelse(d$pir<1,'Below_1','At_least_1')),levels=c('Below_1','At_least_1'))
d$design_valid<-with(d,is.finite(analysis_weight)&analysis_weight>0&!is.na(SDMVSTRA)&!is.na(SDMVPSU))
d$age_valid<-with(d,is.finite(age)&age>=20&age<=79&age==floor(age))

master<-d
saveRDS(master,file.path(root,'master_frame.rds'))
base_out<-out
for(scope in c('prepandemic','latest','pooled')) {
 d<-if(scope=='prepandemic')master[master$year<2021,] else if(scope=='latest')master[master$year==2021,] else master
 if(scope=='prepandemic')d$analysis_weight<-d$analysis_weight*23.2/21.2
 if(scope=='latest')d$analysis_weight<-d$official_mec_weight
 d$era<-factor(ifelse(d$year==2021,'latest','prepandemic'),levels=c('prepandemic','latest'))
 out<-file.path(base_out,scope);dir.create(out,showWarnings=FALSE)
 scope_root<-file.path(root,scope);dir.create(scope_root,showWarnings=FALSE)
keep<-rep(TRUE,nrow(d));flow<-list(data.frame(step='All_DEMO',entered=nrow(d),excluded=0,remaining=nrow(d)))
step<-function(label,valid) {
 valid[is.na(valid)]<-FALSE;before<-sum(keep);keep<<-keep&valid
 flow[[length(flow)+1]]<<-data.frame(step=label,entered=before,excluded=before-sum(keep),remaining=sum(keep))
}
step('Age_20_79',d$age_valid);step('Valid_MEC_design',d$design_valid)
for(s in setdiff(unique(d$asthma_status),c('yes','no'))) step(paste0('Exclude_asthma_',s),d$asthma_status!=s)
stopifnot(all(!is.na(d$asthma[keep])))
for(s in setdiff(unique(d$arthritis_status),c('RA','no_arthritis'))) step(paste0('Exclude_arthritis_',s),d$arthritis_status!=s)
stopifnot(all(!is.na(d$ra[keep])))
d$pre_covariate<-keep
missing<-lapply(c('sex','race','education','pir','bmi','smoking'),function(v)data.frame(variable=v,denominator=sum(keep),missing=sum(keep&is.na(d[[v]]))))
for(v in c('sex','race','education','pir','bmi','smoking')) step(paste0('Valid_',v),!is.na(d[[v]]))
d$eligible<-keep
write(bind_rows(flow),'sample_flow');write(bind_rows(missing),'missingness')
quality<-bind_rows(lapply(c('asthma_status','arthritis_status','smoke_status'),function(v) {
 d %>% filter(age_valid) %>% count(year,.data[[v]],name='n') %>% rename(status=all_of(v)) %>% mutate(variable=v)
}))
write(quality,'phenotype_qc')
write(d %>% group_by(year) %>% summarise(demo_n=n(),age_n=sum(age_valid),eligible_n=sum(eligible),ra_n=sum(eligible&ra==1,na.rm=TRUE),asthma_n=sum(eligible&asthma==1,na.rm=TRUE)),'cycle_samples')
write(d %>% filter(age_valid,pre_covariate) %>% count(smoke_status,name='n'),'smoking_missing_reasons')
write(d %>% filter(age_valid,pre_covariate) %>% count(DMDEDUC2,name='n'),'education_raw_counts')
stopifnot(!any(d$arthritis_status[d$age_valid]=='logic_conflict'),!any(d$smoke_status[d$age_valid]=='logic_conflict'))
stopifnot(sum(bind_rows(flow)$excluded)+sum(d$eligible)==nrow(d))
dir.create(file.path(scope_root,'derived'),showWarnings=FALSE)
saveRDS(d,file.path(scope_root,'derived','analysis_frame.rds'))
write_json(list(gate='G3',verdict='pass',n_demo=nrow(d),n_eligible=sum(d$eligible),official_frequency_rows=nrow(checks),all_frequency_checks=all(checks$pass)),file.path(out,'preparation_gate.json'),auto_unbox=TRUE,pretty=TRUE)
cat(scope,'G3 PASS',nrow(d),'total;',sum(d$eligible),'eligible\n')

}
