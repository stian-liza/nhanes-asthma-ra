# Deterministic software figures from saved CSVs. No model fitting or image generation.
args<-commandArgs(trailingOnly=TRUE)
if(length(args)) .libPaths(c(args[1],.libPaths()))
suppressPackageStartupMessages({library(grid);library(ragg);library(ggplot2)})
systemfonts::register_font('NHANES_HEITI_SC',plain=list(path='/System/Library/Fonts/STHeiti Light.ttc',index=1))
font<-'NHANES_HEITI_SC'
base<-'outputs/year_extension_20261008_v01'
out<-'outputs/figure_revision_20261008_v02'
dir.create(out,recursive=TRUE,showWarnings=FALSE)
num<-function(x)format(x,big.mark=',',trim=TRUE,scientific=FALSE)
save_grid<-function(draw,path,w,h){
 ragg::agg_png(paste0(path,'.png'),width=w,height=h,units='in',res=300,background='white');draw();dev.off()
 font<<-'Heiti SC'
 quartz(file=paste0(path,'.pdf'),type='pdf',width=w,height=h,family=font);draw();dev.off()
 font<<-'NHANES_HEITI_SC'
}
gtext<-function(label,x,y,size=11,just='centre')grid.text(label,x=x,y=y,just=just,gp=gpar(fontfamily=font,fontsize=size,col='#171717'))
for(scope in c('prepandemic','latest')) {
 dest<-file.path(out,scope);dir.create(dest,showWarnings=FALSE)
 sub<-read.csv(file.path(base,scope,'subgroups.csv'));ints<-read.csv(file.path(base,scope,'interaction_tests.csv'))
 labels<-c('20-39'='20–39 岁','40-59'='40–59 岁','60-79'='60–79 岁','Male'='男性','Female'='女性')
 for(group in c('agegroup','sex')) {
  d<-sub[sub$subgroup_variable==group,];stopifnot(all(d$status=='estimable'),all(d$lower>.5),all(d$upper<10))
  interaction_p<-ints$p[ints$variable==group]
  draw<-function(){
   grid.newpage();ys<-if(nrow(d)==3)c(.76,.52,.28)else c(.70,.32)
   # Fixed geometry and log scale across all four forests; values above 4 remain visible.
   xx<-function(z).285+(log(z)-log(.5))/(log(10)-log(.5))*.435
   gtext('亚组',.025,.92,11.5,'left');gtext('人数',.205,.92,11.5,'right')
   gtext(sprintf('交互 P = %.4f',interaction_p),.285,.92,11.5,'left')
   gtext('OR（95% CI）',.758,.92,11.5,'left')
   grid.lines(x=c(xx(1),xx(1)),y=c(.16,.84),gp=gpar(col='#777777',lty=2,lwd=1))
   for(i in seq_len(nrow(d))){
    gtext(labels[d$subgroup[i]],.025,ys[i],11.5,'left');gtext(num(d$n[i]),.205,ys[i],11.5,'right')
    grid.lines(x=c(xx(d$lower[i]),xx(d$upper[i])),y=rep(ys[i],2),gp=gpar(lwd=1.3,col='#222222'))
    grid.rect(x=xx(d$OR[i]),y=ys[i],width=unit(3,'mm'),height=unit(3,'mm'),gp=gpar(fill='#245776',col=NA))
    gtext(sprintf('%.2f（%.2f–%.2f）',d$OR[i],d$lower[i],d$upper[i]),.758,ys[i],11.5,'left')
   }
   grid.lines(x=c(xx(.5),xx(10)),y=c(.16,.16),gp=gpar(lwd=1))
   for(v in c(.5,1,2,4,8,10)){
    grid.lines(x=c(xx(v),xx(v)),y=c(.16,.145),gp=gpar(lwd=1));gtext(format(v,trim=TRUE),xx(v),.108,10)
   }
   gtext('调整后 OR（对数刻度）',.5025,.038,11)
  }
  name<-if(group=='agegroup')'age_subgroups'else'sex_subgroups'
  save_grid(draw,file.path(dest,name),8.8,if(group=='agegroup')3.6 else 3)
 }
 # Flow diagram with content labels only, without an overall figure title or number.
 flow<-read.csv(file.path(base,scope,'sample_flow.csv'));pv<-read.csv(file.path(base,scope,'asthma_prevalence.csv'))
 getn<-function(s)flow$remaining[flow$step==s]
 exc<-function(pattern)sum(flow$excluded[grepl(pattern,flow$step)])
 count<-c(getn('All_DEMO'),getn('Age_20_79'),getn('Valid_MEC_design'),getn('Valid_MEC_design')-exc('^Exclude_asthma'),getn('Valid_MEC_design')-exc('^Exclude_asthma')-exc('^Exclude_arthritis'),getn('Valid_smoking'))
 stopifnot(tail(count,1)==sum(pv$n[pv$group %in% c('RA','No_arthritis')]))
 rowlab<-c('人口学调查记录','年龄 20–79 岁','体检权重及抽样设计有效','曾患哮喘信息有效','RA 或明确无关节炎','全部所需协变量完整有效')
 exclusions<-c(paste0('年龄不符合要求\n排除 ',num(exc('^Age_')),' 人'),paste0('体检权重或设计信息无效\n排除 ',num(exc('^Valid_MEC')),' 人'),paste0('哮喘状态未知或无效\n排除 ',num(exc('^Exclude_asthma')),' 人'),paste0('其他关节炎类型或状态未知\n排除 ',num(exc('^Exclude_arthritis')),' 人'),paste0('协变量缺失或无效\n排除 ',num(exc('^Valid_(sex|race|education|pir|bmi|smoking)$')),' 人'))
 draw_flow<-function(){
  grid.newpage();y<-seq(.93,.18,length.out=6)
  for(i in seq_along(y)){
   grid.roundrect(x=.29,y=y[i],width=.51,height=.096,r=unit(1.5,'mm'),gp=gpar(fill='#F3F6F8',col='#557083',lwd=.8))
   gtext(paste0(rowlab[i],'\nn = ',num(count[i])),.29,y[i],11)
   if(i<6){
    middle<-(y[i]+y[i+1])/2
    grid.lines(x=c(.29,.29),y=c(y[i]-.048,y[i+1]+.048),arrow=arrow(length=unit(1.8,'mm')),gp=gpar(lwd=.8))
    grid.lines(x=c(.29,.59),y=c(middle,middle),arrow=arrow(length=unit(1.8,'mm')),gp=gpar(lwd=.8))
    gtext(exclusions[i],.61,middle,10.5,'left')
   }
  }
  gtext(paste0('最终样本：RA ',num(pv$n[pv$group=='RA']),' 人；明确无关节炎 ',num(pv$n[pv$group=='No_arthritis']),' 人'),.5,.055,11)
 }
 save_grid(draw_flow,file.path(dest,'sample_flow'),7.7,8.5)
 # Each covariate diagnostic is also exported as its own figure, without facet titles.
 r<-read.csv(file.path(base,scope,'binned_model_residuals.csv'))
 labs_x<-c(age='年龄（岁）',bmi='BMI（kg/m²）',pir='贫困收入比（PIR）')
 for(v in c('age','bmi','pir')) {
  z<-r[r$variable==v,];stopifnot(nrow(z)>0)
  p<-ggplot(z,aes(mean_x,residual))+geom_hline(yintercept=0,color='grey55',linetype=2)+geom_line(color='#245776',linewidth=.6)+geom_point(color='#245776',size=2)+labs(x=labs_x[v],y='观察比例 − 模型预测比例')+theme_classic(base_family=font,base_size=12)+theme(axis.text=element_text(color='black'),plot.margin=margin(12,15,10,12))
  stem<-file.path(dest,paste0('residual_',v));ggsave(paste0(stem,'.png'),p,width=5.3,height=3.6,dpi=300,device=ragg::agg_png,bg='white')
  quartz(file=paste0(stem,'.pdf'),type='pdf',width=5.3,height=3.6,family='Heiti SC');print(p+theme(text=element_text(family='Heiti SC')));dev.off()
 }
 for(f in c('subgroups.csv','interaction_tests.csv','sample_flow.csv','asthma_prevalence.csv','binned_model_residuals.csv'))file.copy(file.path(base,scope,f),file.path(dest,paste0('source_',f)),overwrite=TRUE)
}
writeLines(capture.output(sessionInfo()),file.path(out,'environment.txt'))
cat('12 independent figures rendered in PNG and vector PDF with Heiti SC; no titles; no models run.\n')
