unit ResNetImgClassifierFrm2;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo,

  System.IOUtils,

  CoreClasses, ListEngine,
  Learn, LearnTypes,
  zAI, zAI_Common, zAI_TrainingTask,
  zDrawEngineInterface_SlowFMX, zDrawEngine, Geometry2DUnit, MemoryRaster,
  MemoryStream64, PascalStrings, UnicodeMixedLib, DoStatusIO, FMX.Layouts, FMX.ExtCtrls;

type
  TResNetImgClassifierForm2 = class(TForm)
    Training_IMGClassifier_Button: TButton;
    Memo1: TMemo;
    Timer1: TTimer;
    ResetButton: TButton;
    ImgClassifierDetectorButton: TButton;
    OpenDialog1: TOpenDialog;
    procedure ImgClassifierDetectorButtonClick(Sender: TObject);
    procedure Training_IMGClassifier_ButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ResetButtonClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
  public
    ai: TAI;
    imgMat: TAI_ImageMatrix;
  end;

var
  ResNetImgClassifierForm2: TResNetImgClassifierForm2;

implementation

{$R *.fmx}


uses ShowImageFrm;

procedure TResNetImgClassifierForm2.ImgClassifierDetectorButtonClick(Sender: TObject);
begin
  OpenDialog1.Filter := TBitmapCodecManager.GetFilterString;
  if not OpenDialog1.Execute then
      exit;

  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      sync_fn, output_fn, index_fn, carHub_fn: U_String;
      mr: TMemoryRaster;
      rnic_hnd: TRNIC_Handle;
      rnic_index: TPascalStringList;
      rnic_vec: TLVec;
      index: Integer;
      n: U_String;
      CarHub_hnd: TMMOD_Handle;
      hub_num: Integer;
    begin
      output_fn := umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady' + C_RNIC_Ext);
      index_fn := umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.index');
      carHub_fn := umlCombineFileName(TPath.GetLibraryPath, 'carhub' + C_MMOD_Ext);

      if (not umlFileExists(output_fn)) or (not umlFileExists(index_fn)) then
        begin
          DoStatus('û��ͼƬ��������ѵ������.');
          exit;
        end;

      mr := NewRasterFromFile(OpenDialog1.FileName);
      DoStatus('�ع���Ƭ�߶�.');
      mr.Scale(2.0);

      // ������ȡrnicģ�ͣ���Ӧ��ʱ��������ʱһ���Զ�ȡģ��
      rnic_hnd := ai.RNIC_Open_Stream(output_fn);
      rnic_index := TPascalStringList.Create;
      rnic_index.LoadFromFile(index_fn);

      // ������ȡmmodģ�ͣ���Ӧ��ʱ��������ʱһ���Զ�ȡģ��
      CarHub_hnd := ai.MMOD_DNN_Open_Stream(carHub_fn);

      // ִ��ģʽʶ��
      rnic_vec := ai.RNIC_Process(rnic_hnd, mr, 64);

      // ��������ȡ����ӽ��ĳ���id
      index := LMaxVecIndex(rnic_vec);

      if index < rnic_index.Count then
        begin
          n := rnic_index[index];
          DoStatus('%s - %f', [n.Text, rnic_vec[index]]);

          // ����������
          if rnic_vec[index] > 0.5 then
            begin
              // ����ģʽʶ�𷵻صĳ��������������ʶ����
              if (n.Same('suv', 'a')) then
                begin
                  // 2��������ʶ��ʶ���������
                  DoStatus('�����������������.');
                  hub_num := ai.DrawMMOD(CarHub_hnd, 0.8, mr, DEColor(1, 0, 0, 1));
                  DoStatus('�ɹ������� %d ���������', [hub_num]);
                  if hub_num > 0 then
                      TThread.Synchronize(Sender, procedure
                      begin
                        ShowImage(mr);
                      end);
                end
              else if n.Same('lady') then
                begin
                  // 2��������ʶ��ʶ������
                  DoStatus('���������沿������.');
                  ai.DrawFace(mr);
                  TThread.Synchronize(Sender, procedure
                    begin
                      ShowImage(mr);
                    end);
                end;
            end
          else
              DoStatus('�޷�ʶ�𳡾�');
        end
      else
          DoStatus('������RNIC�����ƥ��.��Ҫ����ѵ��');

      ai.MMOD_DNN_Close(CarHub_hnd);
      ai.RNIC_Close(rnic_hnd);
      disposeObject(rnic_index);
      disposeObject(mr);
    end);
end;

procedure TResNetImgClassifierForm2.Training_IMGClassifier_ButtonClick(Sender: TObject);
begin
  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      param: PRNIC_Train_Parameter;
      sync_fn, output_fn, index_fn, carHub_fn: U_String;
      m_task: TTrainingTask;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := False;
          ResetButton.Enabled := False;
        end);
      try
        sync_fn := umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.imgMat.sync');
        output_fn := umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady' + C_RNIC_Ext);
        index_fn := umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.index');
        carHub_fn := umlCombineFileName(TPath.GetLibraryPath, 'carhub' + C_MMOD_Ext);

        if (not umlFileExists(carHub_fn)) then
          begin
            // ִ�����ѵ������
            m_task := TTrainingTask.OpenTask(umlCombineFileName(TPath.GetLibraryPath, 'carhub_mmod_training.OX'));
            if zAI.RunTrainingTask(m_task, ai, 'param.txt') then
              begin
                m_task.ReadToFile('�������.svm_dnn_od', carHub_fn);
              end;
            disposeObject(m_task);
          end
        else
            DoStatus('2�����������Ѿ�ѵ������.');

        if (not umlFileExists(output_fn)) or (not umlFileExists(index_fn)) then
          begin
            param := TAI.Init_RNIC_Train_Parameter(sync_fn, output_fn);

            // ����ѵ���ƻ�ʹ��8Сʱ
            param^.timeout := C_Tick_Hour * 8;

            // �����ݶȵĴ�������
            // �������ݶ��У�ֻҪʧЧ�������ȴﵽ���ڸ���ֵ���ݶȾͻῪʼ����
            param^.iterations_without_progress_threshold := 3000;

            // �����ֵ��������netʱʹ�õģ��������ͣ����ǿ��Ի���ͳ�ƵĲο��߶�
            // ��Ϊ��ͼƬ��������ѵ����iterations_without_progress_threshold��ܴ�
            // all_bn_running_stats_window_sizes���������ںܴ�ĵ��������У�����resnet��ÿ��step mini batch�Ļ���size
            // all_bn_running_stats_window_sizes�ǽ���ѵ��ʱ�����Ƶ�
            param^.all_bn_running_stats_window_sizes := 1000;

            // ��ο�od˼·
            // resnetÿ����stepʱ�Ĺ�դ��������
            // ����gpu���ڴ���������趨����
            param^.img_mini_batch := 12;

            // gpuÿ��һ�������������ͣ��ʱ�䵥λ��ms
            // �����������1.15�����ĺ����������������������ڹ�����ͬʱ����̨�����޸о�ѵ��
            zAI.KeepPerformanceOnTraining := 5;

            if ai.RNIC_Train(imgMat, param, index_fn) then
              begin
                DoStatus('ѵ���ɹ�.');
              end
            else
              begin
                DoStatus('ѵ��ʧ��.');
              end;

            TAI.Free_RNIC_Train_Parameter(param);
          end
        else
            DoStatus('ͼƬ�������Ѿ�ѵ������.');
      finally
          TThread.Synchronize(Sender, procedure
          begin
            Training_IMGClassifier_Button.Enabled := True;
            ResetButton.Enabled := True;
          end);
      end;
    end);
end;

procedure TResNetImgClassifierForm2.DoStatusMethod(AText: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(AText);
  Memo1.GoToTextEnd;
end;

procedure TResNetImgClassifierForm2.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // ��ȡzAI������
  ReadAIConfig;
  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();

  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      i, j: Integer;
      imgL: TAI_ImageList;
      detDef: TAI_DetectorDefine;
      tokens: TArrayPascalString;
      n: TPascalString;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := False;
          ResetButton.Enabled := False;
        end);
      ai := TAI.OpenEngine();
      imgMat := TAI_ImageMatrix.Create;
      DoStatus('���ڶ�ȡ����ͼƬ�����.');
      imgMat.LoadFromFile(umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.imgMat'));

      DoStatus('���������ǩ.');
      for i := 0 to imgMat.Count - 1 do
        begin
          imgL := imgMat[i];
          imgL.CalibrationNullDetectorDefineToken(imgL.FileInfo);
          for j := 0 to imgL.Count - 1 do
            if imgL[j].DetectorDefineList.Count = 0 then
              begin
                detDef := TAI_DetectorDefine.Create(imgL[j]);
                detDef.R := imgL[j].Raster.BoundsRect;
                detDef.Token := imgL.FileInfo;
                imgL[j].DetectorDefineList.Add(detDef);
              end;
        end;

      tokens := imgMat.tokens;
      DoStatus('�ܹ��� %d ������', [length(tokens)]);
      for n in tokens do
          DoStatus('"%s" �� %d ��ͼƬ', [n.Text, imgMat.GetTokenCount(n)]);

      TThread.Synchronize(Sender, procedure
        begin
          Training_IMGClassifier_Button.Enabled := True;
          ResetButton.Enabled := True;
        end);
    end);
end;

procedure TResNetImgClassifierForm2.ResetButtonClick(Sender: TObject);
  procedure d(FileName: U_String);
  begin
    DoStatus('ɾ���ļ� %s', [FileName.Text]);
    umlDeleteFile(FileName);
  end;

begin
  d(umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.imgMat.sync'));
  d(umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.imgMat.sync_'));
  d(umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady' + C_RNIC_Ext));
  d(umlCombineFileName(TPath.GetLibraryPath, 'Mini_Car_and_Lady.index'));
  d(umlCombineFileName(TPath.GetLibraryPath, 'carhub' + C_MMOD_Ext));
end;

procedure TResNetImgClassifierForm2.Timer1Timer(Sender: TObject);
begin
  DoStatus;
end;

end.