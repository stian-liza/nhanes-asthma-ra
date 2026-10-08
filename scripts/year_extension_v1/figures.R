.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(ggplot2);library(dplyr);library(grid);library(ragg)})
scope<-commandArgs(trailingOnly=TRUE)[1];out<-file.path('outputs/year_extension_20261008_v01',scope);period_label<-if(scope=='prepandemic')'1999—2020年3月' else '2021年8月—2023年8月';figdir<-file.path(out,'figures');dir.create(figdir,showWarnings=FALSE)
systemfonts::register_font('NHANES_CJK',plain='/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
font<-'NHANES_CJK'
saveplot<-function(p,name,w,h) {
 ggsave(file.path(figdir,paste0(name,'.png')),p,width=w,height=h,dpi=240,device=ragg::agg_png,bg='white')
 # Quartz PDF uses macOS font discovery and embeds the available CJK glyphs.
 grDevices::pdf(file.path(figdir,paste0(name,'_vector.pdf')),width=w,height=h,family='Helvetica');dev.off()
}
flow<-read.csv(file.path(out,'sample_flow.csv'));getn<-function(s) flow$remaining[flow$step==s];exc<-function(pattern)sum(flow$excluded[grepl(pattern,flow$step)])
num<-function(x)format(x,big.mark=',',scientific=FALSE,trim=TRUE)
nodes<-data.frame(x=3.2,y=seq(12,0,-2),label=c(paste0(period_label,' 人口学记录\nn = ',num(getn('All_DEMO'))),paste0('年龄 20—79 岁\nn = ',num(getn('Age_20_79'))),paste0('有效体检权重与抽样设计\nn = ',num(getn('Valid_MEC_design'))),paste0('曾患哮喘信息有效\nn = ',num(getn('Valid_MEC_design')-exc('^Exclude_asthma'))),paste0('RA 或明确无关节炎\nn = ',num(getn('Valid_MEC_design')-exc('^Exclude_asthma')-exc('^Exclude_arthritis'))),paste0('全部协变量完整有效\nn = ',num(getn('Valid_smoking'))),paste0('最终同一分析样本\nRA 组与无关节炎组')))
pv<-read.csv(file.path(out,'asthma_prevalence.csv'));nodes$label[7]<-paste0('最终同一分析样本\nRA ',num(pv$n[pv$group=='RA']),' 人；无关节炎 ',num(pv$n[pv$group=='No_arthritis']),' 人')
exclusions<-data.frame(y=seq(11,3,-2),label=c(paste0('排除年龄不符\n',num(exc('^Age_')),' 人'),paste0('无有效体检权重或设计\n',num(exc('^Valid_MEC')),' 人'),paste0('哮喘信息未知\n',num(exc('^Exclude_asthma')),' 人'),paste0('其他关节炎或状态未知\n',num(exc('^Exclude_arthritis')),' 人'),paste0('协变量缺失或无效\n',num(exc('^Valid_(sex|race|education|pir|bmi|smoking)$')),' 人')))
p<-ggplot()+geom_rect(data=nodes,aes(xmin=.6,xmax=5.8,ymin=y-.52,ymax=y+.52),fill='#F0F4F7',color='#3D5363',linewidth=.4)+geom_text(data=nodes,aes(x=x,y=y,label=label),family=font,size=3.5,lineheight=1.1)+geom_segment(data=data.frame(y=seq(11.45,1.45,-2)),aes(x=3.2,xend=3.2,y=y,yend=y-.9),arrow=arrow(length=unit(.12,'cm')),linewidth=.45)+geom_segment(data=exclusions,aes(x=3.2,xend=6.4,y=y,yend=y),arrow=arrow(length=unit(.12,'cm')),linewidth=.4)+geom_text(data=exclusions,aes(x=6.6,y=y,label=label),hjust=0,family=font,size=3.1,lineheight=1.1)+coord_cartesian(xlim=c(0,10.1),ylim=c(-.8,12.8),clip='off')+theme_void()+theme(plot.margin=margin(5,5,5,5))
ggsave(file.path(figdir,'sample_flow.png'),p,width=7,height=8.5,dpi=240,device=ragg::agg_png,bg='white')
sub<-read.csv(file.path(out,'subgroups.csv'));ints<-read.csv(file.path(out,'interaction_tests.csv'));sub$y<-c(6,5,4,2,1);textx<-max(sub$upper)*1.2;leftx<-min(.8,min(sub$lower)*.85)
sub$label<-c('20—39 岁','40—59 岁','60—79 岁','男性','女性');sub$estimate_text<-sprintf('%.2f (%.2f–%.2f)',sub$OR,sub$lower,sub$upper)
p<-ggplot(sub,aes(y=y))+geom_vline(xintercept=1,linetype='dashed',color='gray45')+geom_segment(aes(x=lower,xend=upper,yend=y),linewidth=.6)+geom_point(aes(x=OR),shape=15,size=3,color='#204F70')+geom_text(aes(x=textx,label=estimate_text),hjust=0,size=3.4,family=font)+scale_x_log10(breaks=c(1,1.5,2,3,4),limits=c(leftx,textx*2.1))+scale_y_continuous(breaks=sub$y,labels=paste0(sub$label,'  n=',num(sub$n)),limits=c(.4,7.2))+annotate('text',x=leftx,y=6.9,label=paste0('年龄交互 P = ',sprintf('%.4f',ints$p[ints$variable=='agegroup'])),hjust=0,family=font,size=3.5)+annotate('text',x=leftx,y=2.9,label=paste0('性别交互 P = ',sprintf('%.4f',ints$p[ints$variable=='sex'])),hjust=0,family=font,size=3.5)+annotate('text',x=textx,y=6.9,label='OR（95% CI）',hjust=0,family=font,size=3.3)+labs(x='RA 相对于明确无关节炎的优势比（对数刻度）',y=NULL)+theme_classic(base_family=font,base_size=11)+theme(axis.line.y=element_blank(),axis.ticks.y=element_blank(),plot.margin=margin(8,12,8,8))
ggsave(file.path(figdir,'subgroup_forest.png'),p,width=7.2,height=4.8,dpi=240,device=ragg::agg_png,bg='white')
# Produce actual vector PDF through quartz, preserving Chinese text.
pdfplot<-p+theme(text=element_text(family='Arial Unicode MS'))
for(i in seq_along(pdfplot$layers)) if(!is.null(pdfplot$layers[[i]]$aes_params$family)) pdfplot$layers[[i]]$aes_params$family<-'Arial Unicode MS'
quartz(file=file.path(figdir,'subgroup_forest.pdf'),type='pdf',width=7.2,height=4.8,family='Arial Unicode MS');print(pdfplot);dev.off()
r<-read.csv(file.path(out,'binned_model_residuals.csv'));r$variable<-factor(r$variable,levels=c('age','bmi','pir'),labels=c('年龄','BMI','PIR'))
p<-ggplot(r,aes(mean_x,residual))+geom_hline(yintercept=0,color='grey60')+geom_line(color='#204F70')+geom_point()+facet_wrap(~variable,scales='free_x')+labs(x='诊断区间内加权均值',y='观察比例减预测比例')+theme_bw(base_family=font,base_size=11)
ggsave(file.path(figdir,'model_residual_diagnostic.png'),p,width=9,height=3.2,dpi=180,device=ragg::agg_png,bg='white')
