.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(survey);library(jsonlite);library(haven)})
scope<-commandArgs(trailingOnly=TRUE)[1];ROOT<-file.path('/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1',scope);O<-file.path('outputs/year_extension_20261008_v01',scope,'supplement')
d<-readRDS(file.path(ROOT,'derived/analysis_frame.rds'));m<-readRDS(file.path(ROOT,'supplement/models.rds'))$models
checks<-list();add<-function(n,x){checks[[length(checks)+1]]<<-data.frame(check=n,pass=isTRUE(x));if(!isTRUE(x))stop(n)}
# Independently reconstruct final clinical/covariate fields, not just inclusion flags.
age<-d$RIDAGEYR;asthma<-ifelse(d$MCQ010==1,1,ifelse(d$MCQ010==2,0,NA))
ra<-ifelse(d$MCQ160A==2,0,ifelse(d$MCQ160A==1 & d$arthritis_type==ifelse(d$year<2011,1,2),1,NA))
ix<-d$eligible
add('age_values',identical(as.numeric(age[ix]),as.numeric(d$age[ix])))
add('asthma_values',identical(asthma[ix],d$asthma[ix]));add('RA_values',identical(ra[ix],d$ra[ix]))
add('BMI_values',identical(d$BMXBMI[ix],d$bmi[ix]));add('PIR_values',identical(d$INDFMPIR[ix],d$pir[ix]))
add('sex_values',identical(c('Male','Female')[d$RIAGENDR[ix]],as.character(d$sex[ix])))
add('race_values',identical(c('Mexican','Other_Hispanic','NH_White','NH_Black','Other_Multiracial')[d$RIDRETH1[ix]],as.character(d$race[ix])))
add('education_values',identical(c('Less_than_9th','9th_11th','High_school','Some_college','College_grad')[d$DMDEDUC2[ix]],as.character(d$education[ix])))
sm<-ifelse(d$SMQ020[ix]==2,'never',ifelse(d$SMQ040[ix]==3,'former','current'));add('smoking_values',identical(sm,as.character(d$smoking[ix])))
# Alternative basis representation must give equivalent fitted probabilities and RA effect.
a<-m$B1;ds<-a$survey.design;k<-read.csv(file.path(O,'knots.csv'));ka<-unlist(k[k$variable=='age',2:4]);kp<-unlist(k[k$variable=='pir',2:4])
NAge<-splines::ns(ds$variables$age,knots=ka[2],Boundary.knots=ka[c(1,3)]);NPir<-splines::ns(ds$variables$pir,knots=kp[2],Boundary.knots=kp[c(1,3)])
ds$variables$na1<-NAge[,1];ds$variables$na2<-NAge[,2];ds$variables$np1<-NPir[,1];ds$variables$np2<-NPir[,2]
nsfit<-svyglm(asthma~ra+na1+na2+np1+np2+bmi+sex+race+education+smoking,design=ds,family=quasibinomial(),control=glm.control(maxit=100,epsilon=1e-12))
add('natural_spline_RA_coefficient_equivalence',abs(coef(nsfit)['ra']-coef(a)['ra'])<1e-9)
add('natural_spline_RA_SE_equivalence',abs(sqrt(vcov(nsfit)['ra','ra'])-sqrt(vcov(a)['ra','ra']))<1e-9)
add('natural_spline_fitted_equivalence',max(abs(fitted(nsfit)-fitted(a)))<1e-9)
# Older-age spline columns are nearly collinear on the restricted domain.
# Verify the reported RA estimate under centered orthogonal age/PIR bases.
old<-m[['agegroup_60-79']];od<-old$survey.design
A<-scale(cbind(od$variables$age,od$variables$age_nl),center=TRUE,scale=FALSE)
P<-scale(cbind(od$variables$pir,od$variables$pir_nl),center=TRUE,scale=FALSE)
AQ<-qr.Q(qr(A));PQ<-qr.Q(qr(P))
od$variables$a1<-AQ[,1];od$variables$a2<-AQ[,2];od$variables$p1<-PQ[,1];od$variables$p2<-PQ[,2]
om<-svyglm(asthma~ra+a1+a2+p1+p2+bmi+sex+race+education+smoking,od,family=quasibinomial(),control=glm.control(maxit=100,epsilon=1e-12))
add('older_age_orthogonal_RA_coefficient',abs(coef(om)['ra']-coef(old)['ra'])<1e-8)
add('older_age_orthogonal_RA_SE',abs(sqrt(vcov(om)['ra','ra'])-sqrt(vcov(old)['ra','ra']))<1e-8)
add('older_age_orthogonal_fitted',max(abs(fitted(om)-fitted(old)))<1e-8)
write.csv(data.frame(model='agegroup_60-79',original_condition=read.csv(file.path(O,'diagnostics.csv'))$scaled_condition_number[read.csv(file.path(O,'diagnostics.csv'))$model=='agegroup_60-79'],orthogonal_condition=kappa(scale(model.matrix(om)[,-1]),exact=TRUE),RA_beta_difference=coef(om)['ra']-coef(old)['ra'],RA_se_difference=sqrt(vcov(om)['ra','ra'])-sqrt(vcov(old)['ra','ra'])),file.path(O,'older_age_basis_validation.csv'),row.names=FALSE)
# Verify all group sample sizes sum to the same original complete-case target.
z<-ds$variables
for(v in (if(scope=='latest')c('agegroup','sex') else c('agegroup','sex','period'))){nn<-sapply(levels(z[[v]]),function(l)nrow(m[[if(v=='period')paste0('period_',l) else paste(v,l,sep='_')]]$model));add(paste(v,'domain_sum'),sum(nn)==sum(d$eligible))}
# Recompute contrasts with explicit coefficient vectors rather than term-test helper.
tests<-read.csv(file.path(O,'tests.csv'))
for(p in (if(scope=='latest')c('agegroup','sex') else c('agegroup','sex','period'))){
 fit<-m[[paste0('int_',p)]];terms<-grep(paste0('^ra:',p),names(coef(fit)));b<-coef(fit)[terms];V<-vcov(fit)[terms,terms,drop=FALSE]
 Fval<-as.numeric(t(b)%*%solve(V,b))/length(b);r<-tests[tests$test==paste0(if(p=='period')'B3' else 'B1','_interaction_',p),]
 add(paste(p,'Wald_F'),abs(Fval-r$F)<1e-10);add(paste(p,'Wald_P'),abs(pf(Fval,length(b),r$df2,lower.tail=FALSE)-r$p)<1e-10)
}
# Verify standardized points using native prediction, separate from explicit matrix code.
mt<-read.csv(file.path(O,'standardized_prevalence.csv'))
for(n in intersect(c('B0','B1','B3'),names(m)))for(g in 0:1){nd<-z;nd$ra<-g;pr<-as.numeric(predict(m[[n]],newdata=nd,type='response',se.fit=FALSE));p<-weighted.mean(pr,weights(ds));r<-mt[mt$model==n & mt$estimand==if(g==1)'RA' else 'No_arthritis',];add(paste(n,g,'native_predict'),abs(p-r$estimate)<1e-12)}
rg<-read.csv(file.path(O,'regression.csv'))
for(i in seq_len(nrow(rg))){r<-rg[i,];add(paste(r$model,'OR'),abs(exp(r$beta)-r$OR)<1e-12);add(paste(r$model,'CI'),max(abs(exp(r$beta+c(-1,1)*qt(.975,r$df)*r$se)-c(r$lower,r$upper)))<1e-12);add(paste(r$model,'P'),abs(2*pt(abs(r$beta/r$se),r$df,lower.tail=FALSE)-r$p)<1e-12)}
add('all_model_diagnostics',all(read.csv(file.path(O,'diagnostics.csv'))$status=='estimable'))
add('all_numerical_checks',all(read.csv(file.path(O,'numerical_validation.csv'))$pass))
out<-do.call(rbind,checks);write.csv(out,file.path(O,'independent_validation.csv'),row.names=FALSE)
write_json(list(verdict='pass',checks=nrow(out),all_pass=all(out$pass),scope='source-derived fields; alternate spline basis; independent Wald tests; native prediction; effect intervals'),file.path(O,'independent_validation.json'),pretty=TRUE,auto_unbox=TRUE)
cat('PASS',nrow(out),'independent checks\n')
