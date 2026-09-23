# Run after imputation diagnostics have been reviewed. Public outputs are aggregates only.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=1)
.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages({library(survey);library(mice);library(splines);library(ggplot2)})
options(survey.lonely.psu='fail')
root<-normalizePath(args[1]);out<-file.path(root,'derived/v03')
review<-jsonlite::read_json('reports/imputation_review.json',simplifyVector=TRUE)
stopifnot(identical(review$verdict,'pass'))
stopifnot(identical(review$imputation_md5,unname(tools::md5sum(file.path(out,'imputations.rds')))))
d<-read.csv(file.path(out,'persons.csv'),na.strings=c('','NA'))
for(v in c('ra_unknown_type','ra_conflict','no_arthritis','asthma_conflict','smoke_conflict'))
  d[[v]]<-tolower(as.character(d[[v]]))=='true'
saved<-readRDS(file.path(out,'imputations.rds'));imp<-saved$imp;ix<-saved$index
stopifnot(imp$m>=30,imp$iteration>=10)
knots<-saved$age_knots
covariates<-c('age','sex','race','education','pir','smoke')
format_data<-function(data) {
  for(v in c('sex','race','education','smoke','cycle')) data[[v]]<-factor(data[[v]])
  data$age1<-data$age2<-data$age3<-NA_real_
  ok<-which(data$age>=20)
  basis<-ns(data$age[ok],knots=knots,Boundary.knots=c(20,80))
  data[ok,c('age1','age2','age3')]<-basis
  data
}

design_for<-function(data,years,outcome='current',restriction='all',complete=FALSE,unknown=NULL) {
  b<-data[data$cycle%in%years,]
  if(!is.null(unknown)) b$ra[b$ra_unknown_type]<-unknown
  b<-format_data(b);b$y<-b[[outcome]]
  if(min(years)>=2001) b$w<-b$WTINT2YR/length(years) else {
    stopifnot(identical(as.integer(years),seq(1999L,2017L,2L)))
    b$w<-b$w_ever20
  }
  stopifnot(all(is.finite(b$w)),all(b$w>0),!anyNA(b$SDMVSTRA),!anyNA(b$SDMVPSU))
  b$eligible<-b$age>=20 & !is.na(b$ra) & !is.na(b$y)
  if(restriction=='no_arthritis') b$eligible<-b$eligible & (b$ra==1 | b$no_arthritis)
  if(restriction=='current_never') b$eligible<-b$eligible & b$asthma_state%in%c('current','never')
  if(complete) b$eligible<-b$eligible & complete.cases(b[,covariates])
  b$eligible[is.na(b$eligible)]<-FALSE
  full<-svydesign(ids=~SDMVPSU,strata=~SDMVSTRA,weights=~w,data=b,nest=TRUE)
  subset(full,eligible)
}

model_formula<-function(level='M2',linear=FALSE) {
  base<-if(linear) 'age' else 'age1+age2+age3'
  as.formula(switch(level,M0='y~ra',M1=paste('y~ra+',base,'+sex+race+cycle'),
                    M2=paste('y~ra+',base,'+sex+race+cycle+education+pir+smoke')))
}

fit_one<-function(des,level='M2',linear=FALSE,margins=FALSE) {
  f<-model_formula(level,linear)
  dat<-des$variables
  cells<-table(factor(dat$ra,levels=0:1),factor(dat$y,levels=0:1))
  mm<-model.matrix(f,dat);p<-ncol(mm)
  stopifnot(min(cells)>=10,min(colSums(cells))>=10*(p-1),qr(mm)$rank==p,degf(des)>p-1)
  fit<-svyglm(f,design=des,family=quasibinomial())
  stopifnot(fit$converged,fit$df.residual>0,all(is.finite(coef(fit))),all(is.finite(vcov(fit))))
  ans<-list(q=unname(coef(fit)['ra']),u=unname(vcov(fit)['ra','ra']),df=fit$df.residual,
            n=nrow(dat),parameters=p,design_df=degf(des),
            min_cell=min(cells),kish=sum(weights(des))^2/sum(weights(des)^2),
            fitted_min=min(fitted(fit)),fitted_max=max(fitted(fit)),
            condition_number=kappa(mm,exact=FALSE))
  if(margins) {
    adj<-svyglm(update(f,.~.-ra),design=des,family=quasibinomial())
    pm<-svypredmeans(adj,~ra,predictat=c(0,1))
    Q<-coef(pm);U<-vcov(pm)
    ans$margin_q<-c(nonRA=Q[1],RA=Q[2],difference=Q[2]-Q[1])
    ans$margin_u<-c(U[1,1],U[2,2],U[1,1]+U[2,2]-2*U[1,2])
    # Independent point-estimate check against direct standardization from full model.
    direct<-sapply(0:1,function(g){tmp<-dat;tmp$ra<-g;weighted.mean(predict(fit,tmp,type='response',se.fit=FALSE),weights(des))})
    stopifnot(max(abs(direct-Q))<1e-7)
  }
  ans
}

pool_scalar<-function(q,u,dfcom,exponentiate=FALSE) {
  m<-length(q)
  if(m==1) {estimate<-q;se<-sqrt(u);df<-dfcom;b<-0;lambda<-0} else {
    z<-mice::pool.scalar(q,u,n=dfcom+1,k=1)
    estimate<-z$qbar;se<-sqrt(z$t);df<-z$df;b<-z$b;lambda<-(1+1/m)*b/z$t
  }
  low<-estimate-qt(.975,df)*se;high<-estimate+qt(.975,df)*se
  data.frame(estimate=if(exponentiate) exp(estimate) else estimate,
             lower=if(exponentiate) exp(low) else low,upper=if(exponentiate) exp(high) else high,
             log_or=if(exponentiate) estimate else NA_real_,std_error=se,df=df,
             p_value=2*pt(-abs(estimate/se),df),m=m,missing_information=lambda,
             mc_error=sqrt(b/m),mc_error_over_se=sqrt(b/m)/se)
}

models<-list();margins_out<-list();diagnostics<-list()
run_set<-function(label,years,outcome='current',restriction='all',MI=TRUE,levels='M2',linear=FALSE,unknown=NULL) {
  for(level in levels) {
    cat('MODEL',label,level,format(Sys.time()),'\n');flush.console()
    fits<-vector('list',if(MI) imp$m else 1)
    for(i in seq_along(fits)) {
      x<-d
      if(MI) {
        z<-complete(imp,i)
        for(v in c('education','pir','smoke')) x[ix,v]<-as.numeric(as.character(z[[v]]))
      }
      des<-design_for(x,years,outcome,restriction,complete=!MI,unknown=unknown)
      fits[[i]]<-fit_one(des,level,linear,margins=label%in%c('primary_MI','ever20_MI')&&level=='M2')
    }
    key<-paste(label,level,sep='_')
    dfcom<-min(sapply(fits,`[[`,'df'))
    models[[key]]<<-cbind(analysis=label,model=level,n=fits[[1]]$n,
                          pool_scalar(sapply(fits,`[[`,'q'),sapply(fits,`[[`,'u'),dfcom,TRUE))
    diagnostics[[key]]<<-data.frame(analysis=label,model=level,n=fits[[1]]$n,
          design_df=fits[[1]]$design_df,residual_df=dfcom,parameters=fits[[1]]$parameters,
          min_cell=fits[[1]]$min_cell,kish=fits[[1]]$kish,
          fitted_min=min(sapply(fits,`[[`,'fitted_min')),fitted_max=max(sapply(fits,`[[`,'fitted_max')),
          condition_number_max=max(sapply(fits,`[[`,'condition_number')),all_converged=TRUE)
    if(!is.null(fits[[1]]$margin_q)) for(j in 1:3) {
      margins_out[[paste(key,j)]]<<-cbind(analysis=label,metric=c('nonRA','RA','difference')[j],
           pool_scalar(sapply(fits,function(x)x$margin_q[j]),sapply(fits,function(x)x$margin_u[j]),dfcom))
    }
    # Checkpoints contain aggregates; individual imputation/model objects stay external.
    write.csv(do.call(rbind,models),'results/tables/association_models.csv',row.names=FALSE)
    write.csv(do.call(rbind,diagnostics),'results/qc/model_diagnostics.csv',row.names=FALSE)
    if(length(margins_out))write.csv(do.call(rbind,margins_out),'results/tables/standardized_prevalence.csv',row.names=FALSE)
  }
}

# Survey descriptions use the disease-known domain before covariate deletion/imputation.
descriptive<-list();four<-list();characteristics<-list();design_audit<-list();point_checks<-list()
for(branch in c('primary','ever20')) {
  years<-seq(if(branch=='primary')2001 else 1999,2017,2)
  outcome<-if(branch=='primary')'current' else 'ever'
  des<-design_for(d,years,outcome)
  ids<-unique(des$variables[,c('SDMVSTRA','SDMVPSU')])
  design_audit[[branch]]<-data.frame(analysis=branch,n=nrow(des),strata=length(unique(ids$SDMVSTRA)),
                                   psu=nrow(ids),df=degf(des),min_psu_per_stratum=min(table(ids$SDMVSTRA)))
  for(cy in c(0,years)) {
    cy_des<-if(cy==0) des else subset(des,as.numeric(as.character(cycle))==cy)
    for(g in 0:1) {
      gd<-subset(cy_des,ra==g)
      p<-svyciprop(~y,gd,method='logit',df=degf(gd)); ci<-confint(p)
      check<-weighted.mean(gd$variables$y,weights(gd))
      point_checks[[paste(branch,cy,g)]]<-data.frame(analysis=branch,cycle=cy,ra=g,
               model_proportion=as.numeric(p),direct_proportion=check,error=abs(as.numeric(p)-check))
      # Iterative logit fitting may differ from the direct ratio at about 1e-9.
      if(abs(as.numeric(p)-check)>=1e-7)
        stop(sprintf('Descriptive point check: %s cycle=%s RA=%s model=%.12g direct=%.12g difference=%.12g',
                     branch,cy,g,as.numeric(p),check,as.numeric(p)-check))
      descriptive[[paste(branch,cy,g)]]<-data.frame(analysis=branch,cycle=if(cy==0)'all' else cy,
          ra=g,n=nrow(gd),asthma_n=sum(gd$variables$y),prevalence=as.numeric(p),lower=ci[1],upper=ci[2])
    }
  }
  for(g in 0:1)for(a in 0:1) {
    cell<-as.numeric(des$variables$ra==g & des$variables$y==a)
    cd<-update(des,cell=cell);p<-svyciprop(~cell,cd,method='logit');ci<-confint(p)
    four[[paste(branch,g,a)]]<-data.frame(analysis=branch,ra=g,asthma=a,n=sum(cell),proportion=as.numeric(p),lower=ci[1],upper=ci[2])
  }
  for(g in 0:1)for(v in covariates) {
    gd<-subset(des,ra==g);values<-gd$variables[[v]]
    miss<-is.na(values);md<-update(gd,missing_flag=as.numeric(miss))
    missing_pct<-as.numeric(svymean(~missing_flag,md))
    if(v%in%c('age','pir')) {
      s<-svymean(as.formula(paste0('~',v)),gd,na.rm=TRUE);ci<-confint(s,df=degf(gd))
      characteristics[[paste(branch,g,v)]]<-data.frame(analysis=branch,ra=g,variable=v,level='mean',
         n=sum(!miss),estimate=coef(s)[1],lower=ci[1],upper=ci[2],missing_n=sum(miss),missing_fraction=missing_pct)
    } else for(lev in levels(values)) {
      z<-as.numeric(values==lev);ld<-update(gd,z=z)
      s<-svyciprop(~z,ld,method='wilson',na.rm=TRUE);ci<-confint(s)
      characteristics[[paste(branch,g,v,lev)]]<-data.frame(analysis=branch,ra=g,variable=v,level=lev,
         n=sum(z,na.rm=TRUE),estimate=as.numeric(s),lower=ci[1],upper=ci[2],missing_n=sum(miss),missing_fraction=missing_pct)
    }
  }
}
write.csv(do.call(rbind,design_audit),'results/qc/design_audit.csv',row.names=FALSE)
write.csv(do.call(rbind,point_checks),'results/qc/descriptive_checks.csv',row.names=FALSE)
write.csv(do.call(rbind,descriptive),'results/tables/asthma_by_ra_cycle.csv',row.names=FALSE)
write.csv(do.call(rbind,four),'results/tables/coexistence_cells.csv',row.names=FALSE)
write.csv(do.call(rbind,characteristics),'results/tables/characteristics.csv',row.names=FALSE)
run_set('primary_MI',seq(2001,2017,2),levels=c('M0','M1','M2'))
run_set('primary_CC',seq(2001,2017,2),MI=FALSE,levels=c('M0','M1','M2'))
run_set('ever20_MI',seq(1999,2017,2),outcome='ever',levels=c('M0','M1','M2'))
run_set('ever20_CC',seq(1999,2017,2),outcome='ever',MI=FALSE)
run_set('no_arthritis_MI',seq(2001,2017,2),restriction='no_arthritis')
run_set('current_never_MI',seq(2001,2017,2),restriction='current_never')
run_set('ever18_MI',seq(2001,2017,2),outcome='ever')
run_set('from2003_MI',seq(2003,2017,2))
run_set('linear_age_MI',seq(2001,2017,2),linear=TRUE)
for(cy in seq(2001,2017,2))run_set(paste0('omit_',cy,'_MI'),setdiff(seq(2001,2017,2),cy))
run_set('unknown_type_as_nonRA_CC',seq(2001,2017,2),MI=FALSE,unknown=0)
run_set('unknown_type_as_RA_CC',seq(2001,2017,2),MI=FALSE,unknown=1)
all_models<-do.call(rbind,models)
sel<-all_models[all_models$model=='M2',]
sel$analysis<-factor(sel$analysis,levels=rev(sel$analysis))
fig<-ggplot(sel,aes(estimate,analysis))+geom_vline(xintercept=1,linetype=2,color='grey50')+
  geom_errorbar(aes(xmin=lower,xmax=upper),orientation='y',width=.15)+geom_point()+
  scale_x_log10()+labs(x='Prevalence odds ratio (95% CI)',y=NULL,
                      title='Self-reported RA and asthma: primary and sensitivity analyses')+theme_bw(base_size=11)
ggsave('results/figures/associations.png',fig,width=10,height=8,dpi=180)
ggsave('results/figures/associations.pdf',fig,width=10,height=8)
capture.output(sessionInfo(),file='reports/session_info.txt')
status<-list(status='computed_pending_review',imputations=imp$m,iterations=imp$iteration,
             secondary='not_started_novelty_gate',primary_mc_error_over_se=all_models$mc_error_over_se[
               all_models$analysis=='primary_MI' & all_models$model=='M2'])
jsonlite::write_json(status,'reports/run_status.json',auto_unbox=TRUE,pretty=TRUE)
cat('ANALYSIS_END',format(Sys.time()),'\n')
