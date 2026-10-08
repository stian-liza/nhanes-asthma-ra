.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(lpSolve);library(survey);library(dplyr);library(jsonlite)})
scope<-commandArgs(trailingOnly=TRUE)[1];stopifnot(scope %in% c('prepandemic','latest','pooled'))
root<-file.path('/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1',scope);out<-file.path('outputs/year_extension_20261008_v01',scope)
write<-function(x,n)write.csv(x,file.path(out,paste0(n,'.csv')),row.names=FALSE,na='')
# Existence of a nonnegative signed margin, positive for at least one observation,
# is complete/quasi separation. Split unrestricted beta into two nonnegative parts.
# L1 <= 1 makes the objective bounded without excluding any separating direction.
separation<-function(X,y) {
 scales<-apply(abs(X),2,max);X<-sweep(X,2,pmax(scales,1),'/');A<-X*(2*y-1);p<-ncol(X)
 C<-rbind(cbind(A,-A),rep(1,2*p))
 fit<-lp('max',c(colSums(A),-colSums(A)),C,c(rep('>=',nrow(A)),'<='),c(rep(0,nrow(A)),1),transpose.constraints=TRUE)
 list(status=fit$status,objective=fit$objval,separated=fit$status==0 && fit$objval>1e-7)
}
stopifnot(separation(cbind(1,c(0,1)),c(0,1))$separated)
stopifnot(!separation(cbind(1,c(0,0,1,1)),c(0,1,0,1))$separated)
checks<-list()
for(path in list.files(file.path(root,'derived'),pattern='^separation_.*[.]rds$',full.names=TRUE)) {
 input<-readRDS(path);label<-sub('^separation_|[.]rds$','',basename(path));label<-sub('[.]rds$','',label)
 r<-separation(input$X,input$y);checks[[length(checks)+1]]<-data.frame(model=label,solver_status=r$status,objective=r$objective,separated=r$separated)
 cat(label,'LP',r$status,'objective',r$objective,'\n')
}
checks<-bind_rows(checks);write(checks,'separation_checks')
stopifnot(all(checks$solver_status==0))
diag<-read.csv(file.path(out,'model_diagnostics.csv'));diag<-left_join(diag,checks,by='model',relationship='one-to-one');stopifnot(!anyNA(diag$separated))
diag$status<-ifelse(diag$status!='not_estimable'&!diag$separated,'estimable','not_estimable');write(diag,'model_diagnostics')
for(file in c('regression','subgroups','all_model_coefficients')) {
 tab<-read.csv(file.path(out,paste0(file,'.csv')));tab$status<-diag$status[match(tab$model,diag$model)]
 invalid<-tab$status=='not_estimable';tab[invalid,c('OR','lower','upper','p')]<-NA;write(tab,file)
}
# Numerical diagnostics preserve specified models; no alternative analyses added.
models<-readRDS(file.path(root,'derived','models.rds'));m<-models$M3;z<-m$survey.design$variables
z$residual<-z$asthma-fitted(m);z$predicted<-fitted(m)
res<-list()
for(v in c('age','bmi','pir')) {
 cuts<-unique(as.numeric(quantile(z[[v]],probs=seq(0,1,length.out=11))))
 z$bin<-cut(z[[v]],cuts,include.lowest=TRUE)
 res[[length(res)+1]]<-z %>% group_by(bin) %>% summarise(n=n(),mean_x=weighted.mean(.data[[v]],analysis_weight),observed=weighted.mean(asthma,analysis_weight),predicted=weighted.mean(predicted,analysis_weight),residual=weighted.mean(residual,analysis_weight),.groups='drop') %>% mutate(variable=v)
}
write(bind_rows(res),'binned_model_residuals')
writeLines(capture.output(sessionInfo()),file.path(out,'environment_diagnostics.txt'))
write_json(list(G4='pass',G5=if(all(diag$status[diag$model %in% c('M0','M1','M2','M3')]=='estimable'))'pass' else 'not_estimable_items_reported',G6=if(all(diag$status=='estimable'))'pass' else 'not_estimable_items_reported',separation_method='bounded linear program for signed nonnegative margins',solver='lpSolve',threshold=1e-7),file.path(out,'model_gate.json'),auto_unbox=TRUE,pretty=TRUE)
