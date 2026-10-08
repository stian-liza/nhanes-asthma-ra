# Design-based estimates only. Requires audited fresh-run participant frame.
.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(survey);library(dplyr);library(jsonlite)})
options(survey.lonely.psu='fail',survey.adjust.domain.lonely=FALSE)
scope<-commandArgs(trailingOnly=TRUE)[1];stopifnot(scope %in% c('prepandemic','latest','pooled'))
root<-file.path('/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1',scope)
out<-file.path('outputs/year_extension_20261008_v01',scope)
write<-function(x,n) write.csv(x,file.path(out,paste0(n,'.csv')),row.names=FALSE,na='')
stopifnot(fromJSON(file.path(out,'preparation_gate.json'))$verdict=='pass')
d<-readRDS(file.path(root,'derived','analysis_frame.rds'))
broad<-d[d$design_valid,]
# No concatenation of cycle and stratum: the official 1999-2002 strata overlap by design.
wide<-svydesign(ids=~SDMVPSU,strata=~SDMVSTRA,weights=~analysis_weight,data=broad,nest=TRUE)
des<-subset(wide,eligible)
actual<-des$variables
support<-function(ds,label) {
 z<-ds$variables; pairs<-unique(z[,c('SDMVSTRA','SDMVPSU')]);tab<-table(pairs$SDMVSTRA)
 data.frame(domain=label,n=nrow(z),strata=length(tab),psu=nrow(pairs),df=degf(ds),strata_with_one_domain_psu=sum(tab==1),weight_sum=sum(z$analysis_weight),min_weight=min(z$analysis_weight),max_weight=max(z$analysis_weight))
}
audit<-bind_rows(support(wide,'broad_MEC'),support(des,'complete_case'))
stopifnot(audit$strata_with_one_domain_psu[1]==0,degf(des)>0)
write(audit,'design_audit')
write(broad %>% group_by(year,SDMVSTRA) %>% summarise(psu=n_distinct(SDMVPSU),n=n(),.groups='drop'),'cycle_strata')
write(actual %>% count(SDMVSTRA,SDMVPSU,ra,asthma,name='n'),'domain_psu_counts')
# Prevalence: domain df and logit CI; independent point calculation as numerical control.
prev_rows<-list()
for(g in c('All','No_arthritis','RA')) {
 s<-if(g=='All')des else subset(des,ra==ifelse(g=='RA',1,0));z<-s$variables
 est<-as.numeric(coef(svymean(~asthma,s)));manual<-sum(z$analysis_weight*z$asthma)/sum(z$analysis_weight)
 stopifnot(abs(est-manual)<1e-12)
 ci<-c(NA,NA);status<-'estimable'
 if(est>0 & est<1 & degf(s)>0) {
  obj<-try(svyciprop(~asthma,s,method='logit',df=degf(s)),silent=TRUE)
  if(inherits(obj,'try-error'))status<-'CI_not_estimable' else ci<-as.numeric(confint(obj))
 }else status<-'CI_not_estimable'
 prev_rows[[length(prev_rows)+1]]<-data.frame(group=g,n=nrow(z),events=sum(z$asthma),estimate=est,lower=ci[1],upper=ci[2],df=degf(s),method='survey logit CI',status,manual_difference=est-manual)
}
write(bind_rows(prev_rows),'asthma_prevalence')
# Descriptive table: continuous weighted mean and SE; categorical n and weighted percentage.
char<-list();quant<-list()
for(g in c('All','No_arthritis','RA')) {
 s<-if(g=='All')des else subset(des,ra==ifelse(g=='RA',1,0));z<-s$variables
 for(v in c('age','bmi','pir')) {
  m<-svymean(reformulate(v),s)
  char[[length(char)+1]]<-data.frame(group=g,variable=v,level='continuous',n=nrow(z),estimate=as.numeric(coef(m)),se=as.numeric(SE(m)),method='weighted_mean')
  q<-svyquantile(reformulate(v),s,quantiles=c(.25,.5,.75),ci=FALSE,qrule='math')
  quant[[length(quant)+1]]<-data.frame(group=g,variable=v,q25=as.numeric(coef(q))[1],median=as.numeric(coef(q))[2],q75=as.numeric(coef(q))[3],method='survey weighted quantile qrule math')
 }
 for(v in c('agegroup','sex','race','education','pirgroup','bmigroup','smoking')) {
  m<-svymean(reformulate(v),s)
  for(j in seq_along(levels(z[[v]])))char[[length(char)+1]]<-data.frame(group=g,variable=v,level=levels(z[[v]])[j],n=sum(z[[v]]==levels(z[[v]])[j]),estimate=as.numeric(coef(m))[j],se=as.numeric(SE(m))[j],method='weighted_proportion')
 }
}
write(bind_rows(char),'characteristics');write(bind_rows(quant),'continuous_quantiles')
tests<-list();covtab<-list();sparse<-list()
for(y in c('asthma','ra'))for(v in c('agegroup','sex','race','education','pirgroup','bmigroup','smoking')) {
 f<-as.formula(paste('~',v,'+',y));tt<-svychisq(f,des,statistic='F')
 tests[[length(tests)+1]]<-data.frame(outcome=y,variable=v,F=unname(tt$statistic),df1=tt$parameter[1],df2=tt$parameter[2],p=tt$p.value,method=tt$method)
 for(l in levels(actual[[v]])) {
  s<-des[actual[[v]]==l,];z<-s$variables;m<-svymean(reformulate(y),s)
  covtab[[length(covtab)+1]]<-data.frame(outcome=y,variable=v,level=l,n=nrow(z),events=sum(z[[y]]),estimate=as.numeric(coef(m)),se=as.numeric(SE(m)))
  sparse[[length(sparse)+1]]<-data.frame(outcome=y,variable=v,level=l,events=sum(z[[y]]),nonevents=sum(1-z[[y]]),warning_small_cell=min(sum(z[[y]]),sum(1-z[[y]]))<5)
 }
}
write(bind_rows(tests),'covariate_tests');ct<-bind_rows(covtab);write(filter(ct,outcome=='asthma'),'covariates_asthma');write(filter(ct,outcome=='ra'),'covariates_ra');write(bind_rows(sparse),'categorical_cells')
# Regression and diagnostics. No data-dependent variable selection.
forms<-list(M0=asthma~ra,M1=asthma~ra+age+sex+race,M2=asthma~ra+age+sex+race+education+pir,M3=asthma~ra+age+sex+race+education+pir+bmi+smoking)
models<-list();diagnostics<-list();coefficients<-list();cells<-list();domain_support<-list();separation_inputs<-list()
fit_one<-function(ds,formula,label) {
 z<-ds$variables; warn<-character();nu<-degf(ds)
 tab<-as.data.frame(table(ra=z$ra,asthma=z$asthma));names(tab)[3]<-'n';tab$model<-label;cells[[length(cells)+1]]<<-tab
 domain_support[[length(domain_support)+1]]<<-support(ds,label)
 X<-model.matrix(formula,z);scaled<-scale(X[,-1,drop=FALSE]);cond<-kappa(scaled,exact=TRUE)
 fit<-withCallingHandlers(tryCatch(svyglm(formula,ds,family=quasibinomial(),control=glm.control(maxit=100,epsilon=1e-12)),error=function(e)e),warning=function(w){warn<<-c(warn,conditionMessage(w));invokeRestart('muffleWarning')})
 if(inherits(fit,'error')) {
  diagnostics[[length(diagnostics)+1]]<<-data.frame(model=label,n=nrow(z),events=sum(z$asthma),df=nu,rank=qr(X)$rank,columns=ncol(X),condition_number=cond,converged=FALSE,iterations=NA,max_abs_beta=NA,max_se=NA,min_fitted=NA,max_fitted=NA,status='not_estimable',warnings=conditionMessage(fit))
  return(data.frame(model=label,term='ra',n=nrow(z),events=sum(z$asthma),beta=NA_real_,se=NA_real_,OR=NA_real_,lower=NA_real_,upper=NA_real_,p=NA_real_,df=nu,status='not_estimable',formula=paste(deparse(formula),collapse=' ')))
 }
 b<-coef(fit);se<-sqrt(diag(vcov(fit)));valid<-fit$converged & qr(X)$rank==ncol(X) & all(is.finite(b)) & all(is.finite(se)) & nu>0
 # LP separation check done independently on same model matrices after this run.
 sep_path<-file.path(root,'derived',paste0('separation_',label,'.rds'));saveRDS(list(X=X,y=z$asthma),sep_path)
 diagnostics[[length(diagnostics)+1]]<<-data.frame(model=label,n=nrow(z),events=sum(z$asthma),df=nu,rank=qr(X)$rank,columns=ncol(X),condition_number=cond,converged=fit$converged,iterations=fit$iter,max_abs_beta=max(abs(b)),max_se=max(se),min_fitted=min(fitted(fit)),max_fitted=max(fitted(fit)),status=ifelse(valid,'pending_separation_check','not_estimable'),warnings=paste(unique(warn),collapse=' | '))
 ci<-qt(.975,nu)*se;p<-2*pt(abs(b/se),nu,lower.tail=FALSE)
 summary_p<-summary(fit,df.resid=nu)$coefficients[,4];stopifnot(max(abs(p-summary_p))<1e-12)
 rr<-data.frame(model=label,term=names(b),n=nrow(z),events=sum(z$asthma),beta=b,se=se,OR=exp(b),lower=exp(b-ci),upper=exp(b+ci),p=p,df=nu,status=ifelse(valid,'pending_separation_check','not_estimable'),formula=paste(deparse(formula),collapse=' '),row.names=NULL)
 coefficients[[length(coefficients)+1]]<<-rr
 models[[label]]<<-fit
 rr[rr$term=='ra',]
}
reg<-bind_rows(lapply(names(forms),function(n)fit_one(des,forms[[n]],n)));stopifnot(length(unique(reg$n))==1)
sub<-list()
for(v in c('agegroup','sex'))for(l in levels(actual[[v]])) {
 ds<-des[actual[[v]]==l,];form<-if(v=='sex')update(forms$M3,.~.-sex) else forms$M3
 label<-paste0(v,'_',gsub('-','_',l));r<-fit_one(ds,form,label)
 if(!is.null(r)){r$subgroup_variable<-v;r$subgroup<-l;sub[[length(sub)+1]]<-r}
}
int<-list()
for(v in c('agegroup','sex')) {
 form<-if(v=='agegroup')update(forms$M3,.~.+agegroup+ra:agegroup) else update(forms$M3,.~.+ra:sex)
 label<-paste0('interaction_',v);fit_one(des,form,label);m<-models[[label]]
 if(!is.null(m)){
  term<-as.formula(paste0('~ra:',v));test<-regTermTest(m,term,df=degf(des),method='Wald')
  int[[length(int)+1]]<-data.frame(variable=v,n=nrow(actual),F=as.numeric(test$Ftest),df1=test$df,df2=test$ddf,p=as.numeric(test$p),method='joint design Wald F; denominator=domain design df')
 }
}
write(reg,'regression');write(bind_rows(sub),'subgroups');write(bind_rows(int),'interaction_tests');write(bind_rows(coefficients),'all_model_coefficients');write(bind_rows(diagnostics),'model_diagnostics');write(bind_rows(cells),'model_ra_asthma_cells');write(bind_rows(domain_support),'model_design_support')
write(as.data.frame(cor(actual[,c('age','bmi','pir')])),'continuous_correlations')
# VIF adjusted for categorical term degrees of freedom: diagnostic only.
vifs<-list()
for(n in names(models)) {
 m<-models[[n]]
 if(length(attr(terms(m),'term.labels'))<2 || grepl('interaction',n))next
 val<-try(car::vif(m),silent=TRUE)
 if(!inherits(val,'try-error')) {
  if(is.matrix(val)) vifs[[length(vifs)+1]]<-data.frame(model=n,term=rownames(val),GVIF=val[,1],Df=val[,2],adjusted=val[,3],row.names=NULL)
  else vifs[[length(vifs)+1]]<-data.frame(model=n,term=names(val),GVIF=as.numeric(val),Df=1,adjusted=sqrt(as.numeric(val)))
 }
}
write(bind_rows(vifs),'collinearity')
saveRDS(models,file.path(root,'derived','models.rds'))
writeLines(capture.output(sessionInfo()),file.path(out,'environment.txt'))
write_json(list(G4='pass',G5='needs separation diagnostic',G6='needs separation diagnostic',n=nrow(actual),events=sum(actual$asthma),ra=sum(actual$ra),df=degf(des),broad_n=nrow(broad)),file.path(out,'analysis_gate.json'),auto_unbox=TRUE,pretty=TRUE)
print(reg[,c('model','n','OR','lower','upper','p')]);print(bind_rows(int))
