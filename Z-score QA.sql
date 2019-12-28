--################################################################################--
--1. Get facotr raw ratios


	Declare @FactorID Int=5334

	If Object_Id(N'tempdb..#Security') Is Not Null
		Drop Table #Security

	Create Table #Security(Securityid Varchar(30),IsDelete Bit)

	insert into #Security
    select  Securityid, 0 From VRA.dbo.UniverseSecurity
		where universeid = 1292
		and date = '2019-12-17'


	If Object_Id(N'tempdb..#FactorZScoresWin') Is Not Null
		Drop Table #FactorZScoresWin

	If Object_Id(N'tempdb..#FactorZScoresWinResults') Is Not Null
		Drop Table #FactorZScoresWinResults

	Create Table #FactorZScoresWin(Date Datetime, SecurityId varchar(50), Value Float)
	Create Table #FactorZScoresWinResults (Date Datetime, SecurityId varchar(50), Value Float, Iteration TinyInt)	


/*
	Factor RawRatio
*/

	--Insert Into #FactorZScoresWin(Date,SecurityId,Value)
	--Select Date=GetDate(),Securityid,Value
	--	From backend.Vrabackend1.dbo.FactorRawRatio_current f (nolock)
	--Where f.FactorId=@FactorID
	--And Exists (Select Top 1 1 From #Security
	--			Where f.Securityid=Securityid)

	Insert Into #FactorZScoresWin(Date,SecurityId,Value)
	Select TOP 50 Date=GetDate(),Securityid, ROW_NUMBER() OVER (ORDER BY Securityid)
	FROM backend.Vrabackend1.dbo.FactorRawRatio_current f (nolock)
	Where f.FactorId=@FactorID
	And Exists (Select Top 1 1 From #Security
				Where f.Securityid=Securityid)

--################################################################################--
--2. Do some data manupulations here 

	select * from #FactorZScoresWin order by SecurityId

	Update #FactorZScoresWin
	set value = 1E+16
	where SecurityId IN ('00030710', '00122810','00163T10', '00164V10')
	--and date > ''

	Update #FactorZScoresWin set value = 1E+16 where SecurityId IN ('03042010')

	--Update #FactorZScoresWin
	--set value = -1E+16
	--where SecurityId IN ()
	
	If Object_Id(N'tempdb..#FactorZScoresWin_Raw') Is Not Null
	Drop Table #FactorZScoresWin_Raw

	select * into #FactorZScoresWin_Raw from #FactorZScoresWin
	

--################################################################################--
--3. Calculate the Zscore Values

    Declare @LoopCntr TinyInt = 1
	Declare @ZScoreFlip Int = 1
    Create Table #Staging_Temp (Date Datetime, SecurityId varchar(50),Value Float,Value2 Float,Flag SmallInt)
    Create Table #GMR_ZScoreByDate (Date Datetime Null,MeanVal Float Null,STDevVal Float Null,ZScoreFlip Int Null,MeanVal2 Float Null,STDevVal2 Float Null,Minvalue Float Null,Maxvalue Float Null)
       
    Insert Into #GMR_ZScoreByDate (Date, MeanVal, STDevVal, ZScoreFlip)
    Select 
                    Date, MeanVal = AVG(Value), STDevVal = STDEV(Value), ZScoreFlip = @ZScoreFlip -- FIX FIX FIX 
            From #FactorZScoresWin
    Group By Date

    --MRS-1567
    Declare @PctOfZero float
    Declare @Iteration int

    Select @PctOfZero = count(*) * 100.0 / (Select count(*) From #FactorZScoresWin) 
            From #FactorZScoresWin
    Where Value = 0
    Group By Value

    If @PctOfZero > 50
            Set @Iteration = 2 --Start with 2
    Else
            Set @Iteration = 5
    --

    While (1=1)
    Begin
            Set @LoopCntr = @LoopCntr + 1 
            Delete From #Staging_Temp

            Insert Into #Staging_Temp (Date, SecurityId, Value, Value2, Flag)
            SELECT 
                        r.Date, 
                        r.SecurityId,
                        Value=ZScoreFlip * (r.Value - MeanVal) / StdevVal, -- ZScore
                        Value2=r.Value, -- Rawratio
                        Flag=Case 
                                When r.Value > MeanVal + 3 * StdevVal Then 1
                                When r.Value < MeanVal - 3 * StdevVal Then -1
                                Else Null
                        End
                    FROM #GMR_ZScoreByDate B 
            INNER JOIN #FactorZScoresWin r
                    On r.Date = B.Date

            Update #GMR_ZScoreByDate
                    Set MinValue = t.MinValue,
                        MaxValue = t.MaxValue
            From (
                        Select  D = Date, MinValue = Min(Value), MaxValue = Max(Value)
                                From #Staging_Temp
                        GROUP BY Date
            ) t
            WHERE Date = D

            Delete From #GMR_ZScoreByDate Where ( MinValue > -5 And MaxValue < 5 ) Or MinValue Is Null

            Insert Into #FactorZScoresWinResults (Date, SecurityId, Value, Iteration)
            Select 
                        Date, SecurityId, Value, @LoopCntr
                    From #Staging_Temp
            WHere Date Not In (Select Date From #GMR_ZScoreByDate)

            Delete From #Staging_Temp Where Date Not In (Select Date From #GMR_ZScoreByDate)

            Update #GMR_ZScoreByDate
                        Set MeanVal2 = t.MeanVal2,
                                STDevVal2 = t.STDevVal2
                    From (
                        Select 
                                        D = Date, MeanVal2 = AVG(Value2), STDevVal2 = STDEV(Value2)
                                From #Staging_Temp
                        Where Flag Is Null
                        GROUP BY Date
            ) t
            WHERE Date = D

            Update #Staging_Temp
                    set 
                        value2 = b.MeanVal2 + 3 * STDevVal2
                    From #Staging_Temp a
            Join #GMR_ZScoreByDate b
                    On a.Date = b.Date
            Where a.value2 > b.MeanVal2 + 3 * b.STDevVal2 

            Update #Staging_Temp
                    Set 
                        value2 = b.MeanVal2 - 3 * STDevVal2
                    From #Staging_Temp a
            Join #GMR_ZScoreByDate b
                    On a.Date = b.Date
            Where a.value2 < MeanVal2 - 3 * STDevVal2

            Update #GMR_ZScoreByDate
                    Set MeanVal = t.MeanVal,
                        STDevVal = t.STDevVal
            From (
                        Select D = Date, MeanVal = AVG(Value2), STDevVal = STDEV(Value2)
                                From #Staging_Temp
                        Group By Date
            ) t
            Where Date = D

            Delete From #FactorZScoresWin
              
            Insert Into #FactorZScoresWin (Date, SecurityId, Value)
            Select Date, SecurityId, Value2
                    From #Staging_Temp
              
            If @@Rowcount = 0 Or @LoopCntr = @Iteration
            Begin
                    Insert Into #FactorZScoresWinResults (Date, SecurityId, Value, Iteration)
                    SELECT 
                                Date,
                                SecurityId,
                                Value,
                                @LoopCntr
                        FROM #Staging_Temp
                    Break
            End
    End

    Drop Table #Staging_Temp
    Drop Table #GMR_ZScoreByDate


--################################################################################--
--4. Show Result
	Select * from #FactorZScoresWin_Raw order by SecurityId
	Select * from #FactorZScoresWinResults order by SecurityId
